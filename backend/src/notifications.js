// In-app notifications + device push for marketplace, Buy For Me and seller
// events. Every meaningful state change writes a Notification row for the
// affected user and then hands the copy to the push layer (FCM when device
// credentials are configured). In-app delivery is always attempted; push is
// best effort so a misconfigured provider never blocks the event.

import { prisma } from './db.js';

const MAX_NOTIFICATIONS_PER_USER = 50;

export async function createNotification({ userId, type, title, body }) {
  if (!userId) return null;
  const notification = await prisma.notification.create({
    data: { userId, type, title, body: body?.trim() || null },
  });
  await pushToUser(userId, { type, title, body: body?.trim() || '' });
  return notification;
}

async function pushToUser(userId, payload) {
  const serviceAccount = process.env.FIREBASE_SERVICE_ACCOUNT_JSON || process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!serviceAccount) {
    // No push provider configured — the in-app record is the source of truth.
    return { skipped: true };
  }
  try {
    const admin = await loadFirebaseAdmin();
    const messaging = admin?.messaging?.default;
    const user = await prisma.user.findUnique({ where: { id: userId }, select: { fcmToken: true } });
    if (!user?.fcmToken) return { skipped: true };
    await messaging.send({ token: user.fcmToken, notification: { title: payload.title, body: payload.body }, data: { type: payload.type } });
    return { sent: true };
  } catch (error) {
    // Push delivery must never fail the business event that triggered it.
    return { skipped: true, error: String(error?.message || error) };
  }
}

async function loadFirebaseAdmin() {
  try {
    const mod = await import('firebase-admin');
    if (!globalThis.__d2fFirebaseAdmin) {
      globalThis.__d2fFirebaseAdmin = mod.initializeApp(
        process.env.FIREBASE_SERVICE_ACCOUNT_JSON ? { credential: mod.credential.cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON)) } : process.env.FIREBASE_CONFIG ? JSON.parse(process.env.FIREBASE_CONFIG) : {},
        'd2f-push',
      );
    }
    return globalThis.__d2fFirebaseAdmin;
  } catch {
    return null;
  }
}

export async function unreadCount(userId) {
  return prisma.notification.count({ where: { userId, read: false } });
}

export async function listFor(userId, limit = MAX_NOTIFICATIONS_PER_USER) {
  return prisma.notification.findMany({
    where: { userId },
    orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
    take: limit,
  });
}

export async function markRead(id, userId) {
  const notification = await prisma.notification.updateMany({
    where: { id, userId },
    data: { read: true },
  });
  if (notification.count === 0) return null;
  return prisma.notification.findUnique({ where: { id } });
}

export async function markAllRead(userId) {
  const result = await prisma.notification.updateMany({ where: { userId, read: false }, data: { read: true } });
  return result.count;
}

// Marketplace + Buy For Me state changes that need a user-facing alert.
export const notifyOrderPlaced = (userId, payload) => createNotification({ userId, type: 'ORDER_REQUESTED', ...payload });
export const notifyOrderAccepted = (userId, payload) => createNotification({ userId, type: 'ORDER_ACCEPTED', ...payload });
export const notifyOrderShipped = (userId, payload) => createNotification({ userId, type: 'ORDER_SHIPPED', ...payload });
export const notifyOrderCompleted = (userId, payload) => createNotification({ userId, type: 'ORDER_COMPLETED', ...payload });
export const notifySellerApproved = (userId, payload) => createNotification({ userId, type: 'SELLER_APPROVED', ...payload });
export const notifyBuyerBudgetUpdate = (userId, payload) => createNotification({ userId, type: 'BUY_FOR_ME_UPDATE', ...payload });
