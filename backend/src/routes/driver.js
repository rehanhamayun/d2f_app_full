import { Router } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { warehouseLock, fail } from '../warehouse.js';
import { allocatePackageCodes, recordCollection } from '../package_custody.js';
const router = Router();
router.use(authenticate, requireRole('DRIVER'));
const assigned = user => ({ organizationId: user.organizationId || '__unassigned__', serviceType: { not: 'AIR_TRAVELLER' }, OR: [{ pickupDriverId: user.id, status: { in: ['PICKUP_SCHEDULED', 'PICKED_UP'] }, pickupConfirmedAt: null }, { deliveryDriverId: user.id, status: 'OUT_FOR_DELIVERY' }] });
router.get('/tasks', async (req, res, next) => {
  try { const parcels = await prisma.parcel.findMany({ where: assigned(req.user), include: { items: { orderBy: { position: 'asc' } }, customer: { select: { displayName: true, phone: true } } }, orderBy: { pickupScheduledAt: 'asc' } });
    // Only contacts/addresses needed for the driver's assigned leg are exposed.
    res.json(parcels.map(p => ({ id: p.id, trackingId: p.trackingId, status: p.status, origin: p.origin, destination: p.destination, pickupScheduledAt: p.pickupScheduledAt, pickupAddress: p.status !== 'OUT_FOR_DELIVERY' ? p.pickupAddress : null, contactName: p.status !== 'OUT_FOR_DELIVERY' ? p.customer.displayName : p.recipientName, contactPhone: p.status !== 'OUT_FOR_DELIVERY' ? p.customer.phone : p.recipientPhone, recipientAddress: p.status === 'OUT_FOR_DELIVERY' ? p.recipientAddress : null, items: p.items.filter(i => !i.notCollectedReason).map(i => ({ id: i.id, name: i.name, type: i.type, quantity: i.quantity, packageCode: i.packageCode })) })));
  } catch (e) { next(e); }
});
router.post('/tasks/:id/confirm', async (req, res, next) => {
  try { const result = await prisma.$transaction(async tx => {
    await warehouseLock(tx, req.user.organizationId || '__unassigned__');
    const p = await tx.parcel.findFirst({ where: { id: req.params.id, ...assigned(req.user) } });
    if (!p) fail(404, 'Active assigned driver task not found. Refresh your tasks.');
    const b = req.body || {};
    if (b.confirmed !== true || typeof b.proofReference !== 'string' || !b.proofReference.trim() || b.proofReference.length > 300) fail(400, 'Confirm the actual handover and record its proof reference.');
    const scanned = typeof b.scannedTrackingId === 'string' ? b.scannedTrackingId.trim().toUpperCase() : '';
    const packageMatch = scanned && await tx.parcelItem.findFirst({ where: { parcelId: p.id, packageCode: scanned, notCollectedReason: null } });
    if (scanned !== p.trackingId && !packageMatch) fail(400, 'Scan or enter this shipment’s D2F tracking number.');
    const when = new Date();
    const pickup = p.status !== 'OUT_FOR_DELIVERY';
    const legacy = p.status === 'PICKED_UP';
    if (pickup && ((!legacy && !p.pickupScheduledAt) || !p.pickupTargetLocationId || p.pickupConfirmedAt)) fail(409, 'Dispatch must confirm the pickup appointment and receiving warehouse first.');
    const collection = pickup && !legacy ? await recordCollection(tx, p, b.missedItems) : null;
    if (pickup) await allocatePackageCodes(tx, p);
    if (!pickup && (typeof b.recipientName !== 'string' || !b.recipientName.trim() || b.recipientName.length > 120)) fail(400, 'Record the actual recipient’s name and identity/handover proof.');
    const status = pickup ? 'PICKED_UP' : 'DELIVERED';
    await tx.parcel.update({ where: { id: p.id }, data: pickup ? { status, pickupConfirmedAt: when, pickupConfirmedById: req.user.id, pickupProofReference: b.proofReference.trim(), locationId: null } : { status, deliveredAt: when, deliveredToName: b.recipientName.trim(), deliveryProofType: 'RECIPIENT_CONFIRMATION', deliveryProofReference: b.proofReference.trim(), locationId: null } });
    if (!legacy) await tx.trackingEvent.create({ data: { parcelId: p.id, status, actorId: req.user.id, note: pickup ? `Driver physically confirmed pickup${collection ? ` of ${collection.collected}/${collection.total} packages` : ''}. In driver custody; awaiting warehouse receipt.` : 'Assigned driver confirmed actual recipient delivery and recorded proof.' } });
    await tx.auditLog.create({ data: { actorId: req.user.id, action: legacy ? 'LEGACY_DRIVER_COLLECTION_VERIFIED' : pickup ? 'DRIVER_PICKUP_CONFIRMED' : 'DRIVER_DELIVERY_CONFIRMED', entity: 'Parcel', entityId: p.id, detail: JSON.stringify({ proofReference: b.proofReference.trim(), collection }) } });
    return { trackingId: p.trackingId, status };
  }); res.status(201).json(result); } catch (e) { next(e); }
});
export default router;
