// Operational alerts are queued transactionally by database triggers and
// delivered by the push worker. This module serves the shared in-app inbox.

import { prisma } from './db.js';

const MAX_NOTIFICATIONS_PER_USER = 50;

export async function createNotification({ userId, type, title, body }) {
  if (!userId) return null;
  const notification = await prisma.notification.create({
    data: { userId, type, title, body: body?.trim() || null },
  });
  return notification;
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
