import { fail } from './warehouse.js';
import { validText } from './shopfront.js';

export const marketplaceDeliveryMethods = ['SELLER_DELIVERY', 'D2F_DELIVERY', 'EXTERNAL_CARRIER', 'CUSTOMER_PICKUP'];
export const marketplaceDeliveryMethod = order => order.deliveryMethod ?? (order.deliveryPreference === 'SELLER' ? 'SELLER_DELIVERY' : 'D2F_DELIVERY');
export const marketplaceTransitions = {
  REQUESTED: ['ACCEPTED', 'CANCELLED'],
  ACCEPTED: ['PROCESSING', 'CANCELLED'],
  PROCESSING: ['SHIPPED', 'CANCELLED'],
  SHIPPED: ['DELIVERED', 'FAILED_DELIVERY'],
  FAILED_DELIVERY: ['PROCESSING', 'CANCELLED'],
  DELIVERED: ['COMPLETED'],
  COMPLETED: [],
  CANCELLED: [],
};

export function requirePaid(order) {
  if (order.paymentStatus !== 'VERIFIED') fail(409, 'D2F must verify payment before fulfillment.');
  if (order.marketplaceIssues?.some(issue => issue.status === 'OPEN')) fail(409, 'Resolve the open order issue before continuing.');
  const refunded = order.marketplaceIssues?.filter(issue => issue.type === 'REFUND' && issue.status === 'RESOLVED')
    .reduce((sum, issue) => sum + (issue.amountMinor ?? 0), 0) ?? 0;
  if (refunded > 0 && refunded >= order.amountMinor) fail(409, 'This order was fully refunded.');
}

export function deliveryRequirement(order, { carrier, externalRef, parcelId, shipmentEvidence }) {
  const method = marketplaceDeliveryMethod(order);
  if (method === 'D2F_DELIVERY') {
    if (!parcelId) fail(400, 'Link the buyer’s D2F parcel before recording dispatch.');
  } else if (method === 'EXTERNAL_CARRIER') {
    if (!validText(carrier, 120) || !validText(externalRef, 120) || !validText(shipmentEvidence, 500)) fail(400, 'Enter the carrier, its tracking number and a shipment proof reference.');
  } else if (!validText(shipmentEvidence, 500)) {
    fail(400, method === 'CUSTOMER_PICKUP' ? 'Record a reference for the parcel held for pickup.' : 'Record proof that the package was dispatched.');
  }
}

export async function marketplaceNotice(tx, order, type, body) {
  const customer = await tx.customer.findUnique({ where: { id: order.customerId }, select: { userId: true } });
  if (!customer?.userId) return;
  await tx.notification.create({ data: {
    userId: customer.userId, type, title: 'Marketplace order', body: `${order.title} · ${body}`,
    entityType: 'ServiceOrder', entityId: order.id,
  } });
}

export async function marketplaceInvoice(tx, order) {
  const [customer, seller, organization] = await Promise.all([
    tx.customer.findUniqueOrThrow({ where: { id: order.customerId }, select: { displayName: true } }),
    order.sellerId ? tx.sellerProfile.findUnique({ where: { id: order.sellerId }, select: { displayName: true, businessName: true, city: true, country: true } }) : null,
    tx.organization.findUniqueOrThrow({ where: { id: order.organizationId }, select: { name: true } }),
  ]);
  return {
    number: `D2F-MP-${order.id.toUpperCase()}`,
    issuedAt: new Date().toISOString(),
    issuer: seller?.businessName || seller?.displayName || organization.name,
    issuerLocation: [seller?.city, seller?.country].filter(Boolean).join(', '),
    buyer: order.recipientName || customer.displayName,
    orderId: order.id,
    item: order.title,
    quantity: order.quantity,
    unitPriceMinor: order.amountMinor / order.quantity,
    subtotalMinor: order.amountMinor,
    totalMinor: order.amountMinor,
    currency: order.currency,
  };
}

export const orderIssueKinds = ['RETURN', 'REFUND', 'DISPUTE'];
export async function openOrderIssue(tx, req, order, input) {
  const { type, reason, evidence } = input || {};
  if (!orderIssueKinds.includes(type) || !validText(reason, 1000) || (evidence != null && !validText(evidence, 500))) fail(400, 'Choose an issue type and give a reason. Use an evidence reference if available.');
  if (order.status === 'REQUESTED') fail(409, 'A requested order can be cancelled directly.');
  if (type === 'RETURN' && !['DELIVERED', 'COMPLETED'].includes(order.status)) fail(409, 'A return can be requested after delivery.');
  if (type === 'REFUND' && order.paymentStatus !== 'VERIFIED') fail(409, 'A refund requires a verified payment.');
  if (order.marketplaceIssues.some(issue => issue.type === type && issue.status === 'OPEN')) fail(409, 'There is already an open request of this type.');
  const issue = await tx.marketplaceOrderIssue.create({ data: { serviceOrderId: order.id, type, reason: reason.trim(), evidence: evidence?.trim(), openedById: req.user.id } });
  await tx.auditLog.create({ data: { actorId: req.user.id, entity: 'ServiceOrder', entityId: order.id, action: 'MARKETPLACE_ISSUE_OPENED', detail: JSON.stringify({ issueId: issue.id, type, reason: issue.reason }) } });
  await marketplaceNotice(tx, order, `ORDER_${type}_OPEN`, `${type.toLowerCase()} request opened`);
  return issue;
}

export async function refundTotal(tx, orderId) {
  const result = await tx.marketplaceOrderIssue.aggregate({ where: { serviceOrderId: orderId, type: 'REFUND', status: 'RESOLVED' }, _sum: { amountMinor: true } });
  return result._sum.amountMinor || 0;
}

export async function payableBalance(tx, sellerId, currency) {
  const orders = await tx.serviceOrder.findMany({ where: { sellerId, currency, kind: 'MARKETPLACE', status: 'COMPLETED', paymentStatus: 'VERIFIED', deliveryConfirmedAt: { not: null } },
    select: { amountMinor: true, sellerNetMinor: true, marketplaceIssues: { select: { type: true, status: true, amountMinor: true } } } });
  const eligible = orders.filter(order => !order.marketplaceIssues.some(issue => issue.status === 'OPEN'));
  const earned = eligible.reduce((sum, order) => {
    const refunded = order.marketplaceIssues.filter(issue => issue.type === 'REFUND' && issue.status === 'RESOLVED').reduce((n, issue) => n + (issue.amountMinor || 0), 0);
    return sum + Math.floor((order.sellerNetMinor || 0) * Math.max(0, order.amountMinor - refunded) / (order.amountMinor || 1));
  }, 0);
  const payouts = await tx.sellerPayout.aggregate({ where: { sellerId, currency, status: 'PAID' }, _sum: { amountMinor: true } });
  return earned - (payouts._sum.amountMinor || 0);
}
