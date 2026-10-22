import { Router } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { generateTrackingId } from '../tracking.js';

const router = Router();

// ── Domain rules ────────────────────────────────────────────────────────────
const PACKAGE_TYPES = ['BOX', 'BARREL', 'TV', 'APPLIANCE', 'FURNITURE', 'PALLET', 'VEHICLE', 'DOCUMENTS', 'OTHER'];
const METHODS = ['AIR', 'SEA', 'ROAD'];

// Forward-only transitions per the ocean lifecycle
// (registered → processing → in transit → arrived → ready → delivered)
const TRANSITIONS = {
  REQUESTED: ['RECEIVED'],
  RECEIVED: ['PROCESSING', 'IN_TRANSIT'],
  PROCESSING: ['IN_TRANSIT', 'ARRIVED_LOME'],
  IN_TRANSIT: ['ARRIVED_LOME'],
  ARRIVED_LOME: ['READY_FOR_PICKUP'],
  READY_FOR_PICKUP: ['DELIVERED'],
  DELIVERED: [],
};

router.use(authenticate, requireRole('STAFF', 'ADMIN'));

// POST /parcels — register a new parcel (STAFF/ADMIN)
router.post('/', requireRole('STAFF', 'ADMIN'), async (req, res, next) => {
  try {
    const {
      customerId,
      recipientName,
      recipientPhone,
      recipientAddress,
      packageType,
      weightKg,
      origin,
      destination,
      method = 'SEA',
      notes,
      clientRequestId,
    } = req.body || {};

    // Validation
    const missing = [];
    if (!customerId) missing.push('customerId');
    if (!recipientName?.trim()) missing.push('recipientName');
    if (!packageType) missing.push('packageType');
    if (weightKg == null || !Number.isFinite(Number(weightKg)) || Number(weightKg) <= 0) missing.push('weightKg');
    if (!origin?.trim()) missing.push('origin');
    if (!destination?.trim()) missing.push('destination');
    if (missing.length) {
      return res.status(400).json({ error: `Missing or invalid fields: ${missing.join(', ')}` });
    }
    if (!METHODS.includes(method)) {
      return res.status(400).json({ error: `method must be one of ${METHODS.join(', ')}` });
    }
    if (!PACKAGE_TYPES.includes(packageType)) {
      return res.status(400).json({ error: `packageType must be one of ${PACKAGE_TYPES.join(', ')}` });
    }

    // Idempotency: same clientRequestId returns the original record
    if (clientRequestId) {
      const existing = await prisma.parcel.findUnique({ where: { clientRequestId } });
      if (existing) {
        return res.status(200).json(existing);
      }
    }

    const customer = await prisma.customer.findUnique({ where: { id: customerId } });
    if (!customer) return res.status(404).json({ error: 'Customer not found' });

    let createdNew = true;
    const parcel = await prisma.$transaction(async (tx) => {
      const trackingId = await generateTrackingId(tx);
      // Recheck after acquiring the lock: concurrent retries may have committed.
      if (clientRequestId) {
        const existing = await tx.parcel.findUnique({ where: { clientRequestId } });
        if (existing) { createdNew = false; return existing; }
      }
      const created = await tx.parcel.create({
        data: {
          trackingId,
          customerId,
          recipientName: recipientName.trim(),
          recipientPhone: recipientPhone?.trim() || null,
          recipientAddress: recipientAddress?.trim() || null,
          packageType,
          weightKg: Number(weightKg),
          origin: origin.trim(),
          destination: destination.trim(),
          method,
          notes: notes?.trim() || null,
          status: 'RECEIVED',
          createdById: req.user.id,
          locationId: req.user.locationId || null,
          clientRequestId: clientRequestId || null,
        },
      });

      // trackingIndex: public tracking ID → parcel lookup (QR payload source)
      await tx.trackingIndex.create({
        data: { trackingId, parcelId: created.id },
      });

      await tx.trackingEvent.create({
        data: {
          parcelId: created.id,
          status: 'RECEIVED',
          note: 'Parcel registered at intake',
          location: origin.trim(),
          actorId: req.user.id,
        },
      });

      await tx.auditLog.create({
        data: {
          actorId: req.user.id,
          action: 'PARCEL_REGISTER',
          entity: 'Parcel',
          entityId: created.id,
          detail: `trackingId=${trackingId}`,
        },
      });

      return created;
    });

    res.status(createdNew ? 201 : 200).json(parcel);
  } catch (e) {
    next(e);
  }
});

// GET /parcels — list with optional ?status= and ?q= (search trackingId/recipient)
router.get('/', async (req, res, next) => {
  try {
    const { status, q } = req.query;
    const where = {};

    if (status && status !== 'ALL') {
      where.status = Array.isArray(status) ? { in: status } : status;
    }
    if (q?.toString().trim()) {
      const term = q.toString().trim();
      where.OR = [
        { trackingId: { contains: term, mode: 'insensitive' } },
        { recipientName: { contains: term, mode: 'insensitive' } },
      ];
    }

    const parcels = await prisma.parcel.findMany({
      where,
      include: { customer: { select: { id: true, displayName: true } } },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });

    res.json(parcels);
  } catch (e) {
    next(e);
  }
});

// GET /parcels/stats — chip counts for the list screen
router.get('/stats', async (req, res, next) => {
  try {
    const grouped = await prisma.parcel.groupBy({ by: ['status'], _count: { _all: true } });
    const counts = {};
    for (const g of grouped) counts[g.status] = g._count._all;
    res.json(counts);
  } catch (e) {
    next(e);
  }
});

// POST /parcels/:id/events — record status update (STAFF/ADMIN)
// Accepts either the internal UUID or the public tracking ID.
router.post('/:id/events', requireRole('STAFF', 'ADMIN'), async (req, res, next) => {
  try {
    let parcel = await prisma.parcel.findUnique({ where: { id: req.params.id } });
    if (!parcel) {
      parcel = await prisma.parcel.findUnique({ where: { trackingId: req.params.id.toUpperCase() } });
    }
    if (!parcel) return res.status(404).json({ error: 'Parcel not found' });

    const { status, note, location } = req.body || {};
    if (!status || !TRANSITIONS[parcel.status]?.includes(status)) {
      const allowed = TRANSITIONS[parcel.status] || [];
      return res.status(400).json({
        error: `Invalid transition ${parcel.status} → ${status || '(none)'}. Allowed: ${allowed.join(', ') || 'none'}`,
      });
    }
    if (location && typeof location !== 'string') {
      return res.status(400).json({ error: 'location must be a string' });
    }

    const event = await prisma.$transaction(async (tx) => {
      const updated = await tx.parcel.updateMany({
        where: { id: parcel.id, status: parcel.status }, data: { status },
      });
      if (updated.count !== 1) {
        const conflict = new Error('The parcel was updated by another request. Refresh and try again.');
        conflict.status = 409;
        throw conflict;
      }
      const recorded = await tx.trackingEvent.create({ data: {
        parcelId: parcel.id, status, note: note?.trim() || null,
        location: location?.trim() || null, actorId: req.user.id,
      } });
      await tx.auditLog.create({ data: {
        actorId: req.user.id, action: 'PARCEL_STATUS_UPDATE', entity: 'Parcel',
        entityId: parcel.id, detail: `${parcel.status} → ${status}${location ? ` @ ${location}` : ''}`,
      } });
      return recorded;
    });

    res.status(201).json(event);
  } catch (e) {
    next(e);
  }
});

// GET /parcels/:idOrTracking — detail incl. event history
router.get('/:idOrTracking', async (req, res, next) => {
  try {
    const { idOrTracking } = req.params;

    let parcel = await prisma.parcel.findUnique({
      where: { id: idOrTracking },
      include: {
        customer: { select: { id: true, displayName: true, email: true, phone: true } },
        events: { orderBy: { createdAt: 'asc' }, include: { actor: { select: { fullName: true } } } },
      },
    });

    if (!parcel) {
      parcel = await prisma.parcel.findUnique({
        where: { trackingId: idOrTracking.toUpperCase() },
        include: {
          customer: { select: { id: true, displayName: true, email: true, phone: true } },
          events: { orderBy: { createdAt: 'asc' }, include: { actor: { select: { fullName: true } } } },
        },
      });
    }

    if (!parcel) return res.status(404).json({ error: 'Parcel not found' });
    res.json(parcel);
  } catch (e) {
    next(e);
  }
});

export default router;
