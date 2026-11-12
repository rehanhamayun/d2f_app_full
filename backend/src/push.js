import { prisma } from './db.js';

export async function firebaseMessaging() {
  if (!process.env.FIREBASE_SERVICE_ACCOUNT_JSON && !process.env.GOOGLE_APPLICATION_CREDENTIALS) return null;
  const { initializeApp, getApps, cert, applicationDefault } = await import('firebase-admin/app');
  const { getMessaging } = await import('firebase-admin/messaging');
  const app = getApps().find(a => a.name === 'd2f-push') || initializeApp({
    credential: process.env.FIREBASE_SERVICE_ACCOUNT_JSON
      ? cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON)) : applicationDefault(),
  }, 'd2f-push');
  return getMessaging(app);
}

// Commit the in-app alert with the business event, then deliver asynchronously.
// Each device has its own retry state. Leases allow safe multi-replica workers.
export async function drainPush({ db = prisma, messaging, now = new Date() } = {}) {
  messaging ??= await firebaseMessaging();
  if (!messaging) return;
  const pending = await db.notification.findMany({ where: { pushQueuedAt: null }, orderBy: { createdAt: 'asc' }, take: 100 });
  for (const n of pending) {
    await db.$transaction(async tx => {
      const devices = await tx.pushDevice.findMany({ where: { userId: n.userId }, select: { id: true } });
      if (devices.length) await tx.pushDelivery.createMany({ data: devices.map(d => ({ notificationId: n.id, deviceId: d.id, nextAttemptAt: now })), skipDuplicates: true });
      await tx.notification.update({ where: { id: n.id }, data: { pushQueuedAt: now } });
    });
  }
  const rows = await db.pushDelivery.findMany({ where: { completedAt: null, nextAttemptAt: { lte: now }, OR: [{ leaseUntil: null }, { leaseUntil: { lt: now } }] }, include: { notification: true, device: true }, take: 100, orderBy: { nextAttemptAt: 'asc' } });
  for (const row of rows) {
    const claimAt = new Date(Math.max(Date.now(), now.getTime()));
    const claimed = await db.pushDelivery.updateMany({ where: { id: row.id, completedAt: null, OR: [{ leaseUntil: null }, { leaseUntil: { lt: claimAt } }] }, data: { leaseUntil: new Date(claimAt.getTime() + 120000), attempts: { increment: 1 } } });
    if (!claimed.count) continue;
    try {
      // Account changes on a shared device must never expose another user's alert.
      const device = await db.pushDevice.findUnique({ where: { id: row.deviceId }, include: { user: { select: { isActive: true } } } });
      if (device?.userId === row.notification.userId && device.user.isActive) {
        const n = row.notification;
        await messaging.send({ token: device.token, notification: { title: n.title, body: n.body || '' },
          data: { notificationId: n.id, type: n.type, entityType: n.entityType || '', entityId: n.entityId || '' },
          android: { priority: 'high' }, apns: { payload: { aps: { sound: 'default' } } } });
      }
      await db.pushDelivery.updateMany({ where: { id: row.id }, data: { completedAt: new Date(), leaseUntil: null, lastError: null } });
    } catch (error) {
      const code = error.code || 'push/unavailable';
      if (['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(code)) {
        await db.pushDevice.deleteMany({ where: { id: row.deviceId, token: row.device.token } });
      } else {
        await db.pushDelivery.updateMany({ where: { id: row.id }, data: {
          leaseUntil: null, lastError: code, ...(row.attempts >= 9 ? { completedAt: new Date() } : {}),
          nextAttemptAt: new Date(now.getTime() + Math.min(3600000, 30000 * 2 ** row.attempts)),
        } });
      }
    }
  }
}

export function startPushWorker() {
  let running = false;
  const tick = async () => {
    if (running) return;
    running = true;
    try { await drainPush(); } catch (e) { console.error('Push worker unavailable:', e.code || e.name); }
    finally { running = false; }
  };
  const timer = setInterval(tick, 10000);
  timer.unref();
  void tick();
  return () => clearInterval(timer);
}
