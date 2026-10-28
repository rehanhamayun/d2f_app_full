import { Router } from 'express';
import { prisma } from '../db.js';
import { fail } from '../warehouse.js';
// Mounted behind the warehouse staff/admin authentication and organization scope.
const router = Router();
for (const [kind, model, field] of [['parcels', 'parcel', 'createdAt'], ['customers', 'customer', 'displayName']]) {
  router.get(`/${kind}`, async (req, res, next) => {
    try {
      const limit = Number(req.query.limit ?? 50), offset = Number(req.query.offset ?? 0);
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100 || !Number.isSafeInteger(offset) || offset < 0) fail(400, 'Invalid page.');
      const q = req.query.q?.toString().trim(), status = req.query.status?.toString();
      if (status && !['ALL', 'REQUESTED', 'PICKUP_SCHEDULED', 'PICKED_UP', 'RECEIVED', 'PROCESSING', 'IN_TRANSIT', 'ARRIVED_LOME', 'ARRIVED_DESTINATION', 'READY_FOR_PICKUP', 'RELEASED', 'DELIVERED'].includes(status)) fail(400, 'Choose a valid shipment status.');
      const where = { organizationId: req.organizationId };
      if (kind === 'parcels') {
        if (status && status !== 'ALL') where.status = status;
        if (q) where.OR = [{ trackingId: { contains: q, mode: 'insensitive' } }, { recipientName: { contains: q, mode: 'insensitive' } }, { customer: { is: { displayName: { contains: q, mode: 'insensitive' } } } }];
      } else if (q) where.OR = [{ displayName: { contains: q, mode: 'insensitive' } }, { email: { contains: q, mode: 'insensitive' } }, { phone: { contains: q } }];
      const [records, total] = await prisma.$transaction([
        prisma[model].findMany({ where, ...(kind === 'parcels' ? { include: { customer: { select: { id: true, displayName: true } } } } : {}), orderBy: [{ [field]: kind === 'parcels' ? 'desc' : 'asc' }, { id: 'asc' }], skip: offset, take: limit }), prisma[model].count({ where }),
      ]);
      res.json({ [kind]: records, total, offset, limit });
    } catch (e) { next(e); }
  });
}
export default router;
