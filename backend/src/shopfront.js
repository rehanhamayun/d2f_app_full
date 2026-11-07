// Shared helpers for the customer-facing shopfront (Marketplace + Buy For Me)
// and the seller studio. Keeps validation, customer upsert and order
// serialization consistent across routers.

import { prisma } from './db.js';
import { resolveOrganizationId } from './tracking.js';

export const validText = (value, max = 200) =>
  typeof value === 'string' && value.trim().length > 0 && value.length <= max;

export const validOptionalText = (value, max = 2000) =>
  value == null || (typeof value === 'string' && value.length <= max);

export const validAmount = (value) =>
  Number.isSafeInteger(value) && value >= 0 && value <= 1000000000;

export const currencies = ['USD', 'EUR', 'XOF'];

export const deliveryPreferences = ['SELLER', 'D2F'];

// Orders leave the customer-safe view with no commercial internals; the
// seller sees the agreed commission (transparency), the buyer never does.
export const customerOrderSelect = {
  id: true,
  kind: true,
  title: true,
  status: true,
  quantity: true,
  amountMinor: true,
  currency: true,
  notes: true,
  source: true,
  deliveryPreference: true,
  recipientName: true,
  deliveryCity: true,
  deliveryStateProvince: true,
  deliveryCountry: true,
  deliveryAddress: true,
  deliveryPostalCode: true,
  budgetMinor: true,
  productCostMinor: true,
  shippingCostMinor: true,
  paymentStatus: true,
  paymentTransactionId: true,
  deliveryService: true,
  shippingCarrier: true,
  shippingTrackingNumber: true,
  shippingLabelUrl: true,
  sourceUrl: true,
  trackingRef: true,
  createdAt: true,
  updatedAt: true,
  // D2F service fees are visible to buyers; commission is seller-only.
  fulfillmentFeeBps: true,
  fulfillmentFeeMinor: true,
  deliveryFeeBps: true,
  deliveryFeeMinor: true,
  parcel: { select: { trackingId: true } },
  product: {
    select: {
      id: true,
      title: true,
      category: true,
      images: { orderBy: { position: 'asc' }, take: 1, select: { id: true } },
    },
  },
  seller: { select: { id: true, displayName: true, city: true, country: true } },
};

// Seller projection: adds the agreed commission and the buyer's delivery
// contact details. Routes redact phone/address while an order is still
// REQUESTED — the seller gets them only after accepting.
export const sellerOrderSelect = {
  ...customerOrderSelect,
  commissionBps: true,
  commissionMinor: true,
  sellerNetMinor: true,
  recipientName: true,
  recipientPhone: true,
  deliveryAddress: true,
};

/** Strip buyer contact details from orders the seller has not accepted yet. */
export function redactUnaccepted(orders) {
  return orders.map((order) =>
    order.status === 'REQUESTED'
      ? { ...order, recipientName: null, recipientPhone: null, deliveryAddress: null }
      : order,
  );
}

/** Resolve (and upsert) the signed-in customer and their organization. */
export async function upsertCustomer(tx, user) {
  const linked = await tx.customer.findUnique({
    where: { userId: user.id },
    select: { organizationId: true },
  });
  const organizationId = await resolveOrganizationId(tx, {
    ...user,
    organizationId: user.organizationId || linked?.organizationId,
  });
  return tx.customer.upsert({
    where: { userId: user.id },
    update: {
      organizationId,
      displayName: user.fullName,
      email: user.email,
      phone: user.phone,
    },
    create: {
      userId: user.id,
      organizationId,
      displayName: user.fullName,
      email: user.email,
      phone: user.phone,
    },
  });
}

/** Commission snapshot from the agreed seller rate (0 for D2F catalog). */
export function commissionFor(amountMinor, seller) {
  const bps = seller?.commissionBps ?? 0;
  return {
    commissionBps: bps,
    commissionMinor: Math.round((amountMinor * bps) / 10000),
  };
}

/** Calculate all fees for an order: commission, fulfillment, delivery, net to seller. */
export function calculateFees(amountMinor, { seller, deliveryPreference = 'D2F', fulfillment = 'D2F', settings } = {}) {
  const commission = seller ? commissionFor(amountMinor, seller) : { commissionBps: 0, commissionMinor: 0 };
  const fulfillmentBps = fulfillment === 'D2F' ? (settings?.defaultFulfillmentFeeBps ?? 500) : 0;
  const deliveryBps = deliveryPreference === 'D2F' ? (settings?.defaultDeliveryFeeBps ?? 300) : 0;
  const fulfillmentFeeMinor = Math.round((amountMinor * fulfillmentBps) / 10000);
  const deliveryFeeMinor = Math.round((amountMinor * deliveryBps) / 10000);
  const totalFees = commission.commissionMinor + fulfillmentFeeMinor + deliveryFeeMinor;
  const sellerNetMinor = Math.max(0, amountMinor - totalFees);
  return {
    commissionBps: commission.commissionBps,
    commissionMinor: commission.commissionMinor,
    fulfillmentFeeBps: fulfillmentBps,
    fulfillmentFeeMinor,
    deliveryFeeBps: deliveryBps,
    deliveryFeeMinor,
    sellerNetMinor,
    totalFees,
  };
}

/**
 * Decrement tracked stock atomically. When stockCount is null the listing is
 * untracked (Fulfillment phase) and always orders fine. Returns false when
 * the requested quantity is unavailable.
 */
export async function reserveStock(tx, productId, quantity) {
  const product = await tx.product.findUnique({
    where: { id: productId },
    select: { stockCount: true },
  });
  if (!product) return false;
  if (product.stockCount == null) return true;
  const updated = await tx.product.updateMany({
    where: { id: productId, stockCount: { gte: quantity } },
    data: { stockCount: { decrement: quantity } },
  });
  return updated.count === 1;
}

/** Restock after a cancellation/decline; no-op for untracked listings. */
export async function releaseStock(tx, productId, quantity) {
  if (!productId) return;
  await tx.product.updateMany({
    where: { id: productId, stockCount: { not: null } },
    data: { stockCount: { increment: quantity } },
  });
}

export async function audit(tx, req, entity, id, action, detail) {
  await tx.auditLog.create({
    data: { actorId: req.user.id, action, entity, entityId: id, detail },
  });
}
