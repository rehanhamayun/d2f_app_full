import { prisma } from './db.js';

// One reminder for an unanswered offer. The organization lock matches Connect's
// write transactions, while eventKey prevents duplicate delivery across workers.
export async function remindConnectTravellers(now = new Date()) {
  const cutoff = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  const candidates = await prisma.$queryRaw`
    SELECT a.id, t."organizationId"
    FROM "ConnectAssignment" a
    JOIN "ConnectTrip" t ON t.id = a."tripId"
    JOIN "User" u ON u.id = t."travellerId"
    WHERE a.status = 'PROPOSED' AND a."createdAt" <= ${cutoff}
      AND t.status = 'APPROVED' AND t."departureAt" > ${now} AND u."isActive" = true
      AND NOT EXISTS (
        SELECT 1 FROM "Notification" n WHERE n."eventKey" = 'connect-offer-reminder:' || a.id
      )
    ORDER BY a."createdAt", a.id LIMIT 100
  `;
  for (const row of candidates) {
    await prisma.$transaction(async tx => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${`connect:${row.organizationId}`}, 0))`;
      const offer = await tx.connectAssignment.findFirst({
        where: { id: row.id, status: 'PROPOSED', trip: { status: 'APPROVED', departureAt: { gt: now }, traveller: { isActive: true } } },
        select: { trip: { select: { id: true, travellerId: true } } },
      });
      if (!offer) return;
      await tx.notification.createMany({
        skipDuplicates: true,
        data: {
          userId: offer.trip.travellerId,
          type: 'CONNECT_OFFER_REMINDER',
          title: 'Traveller response needed',
          body: 'Review the proposed parcel and accept or decline it in D2F Connect.',
          entityType: 'ConnectAssignment',
          entityId: row.id,
          eventKey: `connect-offer-reminder:${row.id}`,
        },
      });
    });
  }
}

export function startConnectReminders() {
  let running = false;
  async function tick() {
    if (running) return;
    running = true;
    try { await remindConnectTravellers(); }
    catch (error) { console.error('Connect reminder worker:', error.message); }
    finally { running = false; }
  }
  const timer = setInterval(tick, 10 * 60 * 1000);
  timer.unref();
  void tick();
  return () => clearInterval(timer);
}
