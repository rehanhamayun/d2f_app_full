import { warehouseLock, fail, locationLabel } from '../warehouse.js';
import { Router } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { generateTrackingId, resolveOrganizationId } from '../tracking.js';
import {
  CONFIRMATION_STATUSES,
  DELIVERY_PROOF_TYPES,
  PARCEL_TRANSITIONS,
  PHYSICAL_STATUSES,
  destinationMatchesLocation,
  facilityDeniedMessage,
  isFacilityAuthorized,
  isLomeLocation,
  resolveFacility,
  sameCity,
  validDate,
  validateRoute,
} from '../parcel_rules.js';

const router = Router();

// ── Domain rules ────────────────────────────────────────────────────────────
const PACKAGE_TYPES = ['BOX', 'BARREL', 'TV', 'APPLIANCE', 'FURNITURE', 'PALLET', 'VEHICLE', 'DOCUMENTS', 'OTHER'];
const METHODS = ['AIR', 'SEA', 'ROAD'];
const text = (value, max = 1000) => typeof value === 'string' && value.trim().length > 0 && value.trim().length <= max;

const parcelInclude = {
  container: { select: { id: true, code: true, status: true } },
  customer: { select: { id: true, displayName: true, email: true, phone: true } },
  events: { orderBy: { createdAt: 'asc' }, include: { actor: { select: { fullName: true } } } },
  transfers: {
    orderBy: { createdAt: 'asc' },
    include: {
      fromLocation: { select: { id: true, name: true, city: true, country: true } },
      toLocation: { select: { id: true, name: true, city: true, country: true } },
      actor: { select: { fullName: true } },
    },
  },
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
      pickupAddress,
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
    if (pickupAddress != null && (typeof pickupAddress !== 'string' || pickupAddress.length > 1000)) {
      return res.status(400).json({ error: 'Pickup address must be at most 1,000 characters.' });
    }
    if (recipientAddress != null && (typeof recipientAddress !== 'string' || recipientAddress.length > 1000)) {
      return res.status(400).json({ error: 'Delivery address must be at most 1,000 characters.' });
    }
    const routeError = validateRoute({
      origin,
      destination,
      method,
      pickupAddress,
      recipientAddress,
    });
    if (routeError) return res.status(400).json({ error: routeError });
    if (req.user.role === 'STAFF' && !req.user.locationId) {
      return res.status(403).json({ error: 'Your account is not assigned to a warehouse. Ask an administrator to assign your facility before receiving parcels.' });
    }

    const organizationId = await resolveOrganizationId(prisma, req.user);

    // Idempotency: same clientRequestId returns the original record
    if (clientRequestId) {
      const existing = await prisma.parcel.findUnique({
        where: { organizationId_clientRequestId: { organizationId, clientRequestId } },
      });
      if (existing) {
        if (existing.organizationId !== organizationId) {
          return res.status(409).json({ error: 'This request identifier has already been used.' });
        }
        return res.status(200).json(existing);
      }
    }

    const customer = await prisma.customer.findUnique({ where: { id: customerId } });
    if (!customer || customer.organizationId !== organizationId) {
      return res.status(404).json({ error: 'Customer not found' });
    }

    let createdNew = true;
    const parcel = await prisma.$transaction(async (tx) => {
      // Retry keys and their locks are isolated to the owning organization.
      if (clientRequestId) {
        await tx.$executeRaw`
          SELECT pg_advisory_xact_lock(hashtextextended(${`${organizationId}:${clientRequestId}`}, 0))
        `;
        const existing = await tx.parcel.findUnique({
          where: { organizationId_clientRequestId: { organizationId, clientRequestId } },
        });
        if (existing) {
          if (existing.organizationId !== organizationId) {
            const conflict = new Error('This request identifier has already been used.');
            conflict.status = 409;
            throw conflict;
          }
          createdNew = false;
          return existing;
        }
      }
      const tracking = await generateTrackingId(tx, organizationId);
      const intake = req.user.locationId
        ? await tx.location.findFirst({ where: { id: req.user.locationId, organizationId } })
        : null;
      const created = await tx.parcel.create({
        data: {
          ...tracking,
          customerId,
          recipientName: recipientName.trim(),
          recipientPhone: recipientPhone?.trim() || null,
          recipientAddress: recipientAddress?.trim() || null,
          pickupAddress: pickupAddress?.trim() || null,
          packageType,
          weightKg: Number(weightKg),
          origin: origin.trim(),
          destination: destination.trim(),
          method,
          notes: notes?.trim() || null,
          status: 'RECEIVED',
          createdById: req.user.id,
          locationId: intake?.id || req.user.locationId || null,
          clientRequestId: clientRequestId || null,
        },
      });

      // trackingIndex: public tracking ID → parcel lookup (QR payload source)
      await tx.trackingIndex.create({
        data: { trackingId: tracking.trackingId, parcelId: created.id },
      });

      await tx.trackingEvent.create({
        data: {
          parcelId: created.id,
          status: 'RECEIVED',
          note: 'Parcel registered at intake',
          location: intake ? locationLabel(intake) : origin.trim(),
          actorId: req.user.id,
        },
      });

      await tx.auditLog.create({
        data: {
          actorId: req.user.id,
          action: 'PARCEL_REGISTER',
          entity: 'Parcel',
          entityId: created.id,
          detail: `trackingId=${tracking.trackingId}`,
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
    const limit = Number(req.query.limit ?? 200);
    const offset = Number(req.query.offset ?? 0);
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 500 || !Number.isSafeInteger(offset) || offset < 0) {
      return res.status(400).json({ error: 'limit must be 1-500 and offset must be a non-negative integer.' });
    }
    const organizationId = await resolveOrganizationId(prisma, req.user);
    const where = { organizationId };

    if (status && status !== 'ALL') {
      const statuses = Array.isArray(status) ? status : String(status).split(',');
      where.status = statuses.length === 1 ? statuses[0] : { in: statuses };
    }
    if (q?.toString().trim()) {
      const term = q.toString().trim();
      where.OR = [
        { trackingId: { contains: term, mode: 'insensitive' } },
        { recipientName: { contains: term, mode: 'insensitive' } },
      ];
    }

    const [parcels, total] = await prisma.$transaction([
      prisma.parcel.findMany({
        where,
        include: { customer: { select: { id: true, displayName: true } } },
        orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
        take: limit,
        skip: offset,
      }),
      prisma.parcel.count({ where }),
    ]);
    res.set('X-Total-Count', String(total));
    res.json(parcels);
  } catch (e) {
    next(e);
  }
});

// GET /parcels/board — one response keeps filter counters and rows consistent.
router.get('/board', async (req, res, next) => {
  try {
    const limit = Number(req.query.limit ?? 200);
    const offset = Number(req.query.offset ?? 0);
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 500 || !Number.isSafeInteger(offset) || offset < 0) {
      return res.status(400).json({ error: 'limit must be 1-500 and offset must be a non-negative integer.' });
    }
    const organizationId = await resolveOrganizationId(prisma, req.user);
    const q = req.query.q?.toString().trim();
    const status = req.query.status?.toString();
    const search = q
      ? {
          OR: [
            { trackingId: { contains: q, mode: 'insensitive' } },
            { recipientName: { contains: q, mode: 'insensitive' } },
          ],
        }
      : {};
    const baseWhere = { organizationId, ...search };
    const listWhere = status && status !== 'ALL' ? { ...baseWhere, status } : baseWhere;
    const [parcels, total, grouped] = await prisma.$transaction([
      prisma.parcel.findMany({
        where: listWhere,
        include: { customer: { select: { id: true, displayName: true } } },
        orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
        take: limit,
        skip: offset,
      }),
      prisma.parcel.count({ where: listWhere }),
      prisma.parcel.groupBy({ by: ['status'], where: baseWhere, _count: { _all: true } }),
    ]);
    const counts = {};
    for (const group of grouped) counts[group.status] = group._count._all;
    res.json({ parcels, total, counts, limit, offset });
  } catch (e) {
    next(e);
  }
});

// GET /parcels/stats — chip counts for the list screen
router.get('/stats', async (req, res, next) => {
  try {
    const organizationId = await resolveOrganizationId(prisma, req.user);
    const q = req.query.q?.toString().trim();
    const grouped = await prisma.parcel.groupBy({
      by: ['status'],
      where: {
        organizationId,
        ...(q
          ? {
              OR: [
                { trackingId: { contains: q, mode: 'insensitive' } },
                { recipientName: { contains: q, mode: 'insensitive' } },
              ],
            }
          : {}),
      },
      _count: { _all: true },
    });
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
    const organizationId = await resolveOrganizationId(prisma, req.user);
    let parcel = await prisma.parcel.findFirst({
      where: { id: req.params.id, organizationId },
    });
    if (!parcel) {
      parcel = await prisma.parcel.findFirst({
        where: { trackingId: req.params.id.toUpperCase(), organizationId },
      });
    }
    if (!parcel) return res.status(404).json({ error: 'Parcel not found' });

    const {
      status,
      note,
      location,
      locationId,
      confirmed,
      releasedToName,
      releasedToIdNumber,
      releasedAt,
      deliveredToName,
      deliveredToIdNumber,
      deliveredAt,
      deliveryProofType,
      deliveryProofReference,
    } = req.body || {};

    if (!status || !PARCEL_TRANSITIONS[parcel.status]?.includes(status)) {
      const allowed = PARCEL_TRANSITIONS[parcel.status] || [];
      return res.status(400).json({
        error: `Invalid transition ${parcel.status} → ${status || '(none)'}. Allowed: ${allowed.join(', ') || 'none'}`,
      });
    }
    if ((location != null && typeof location !== 'string') || (note != null && typeof note !== 'string')) {
      return res.status(400).json({ error: 'location and note must be strings' });
    }
    if (note != null && note.length > 1000) {
      return res.status(400).json({ error: 'The operational note must be at most 1,000 characters.' });
    }
    if (PHYSICAL_STATUSES.has(status) && !locationId && !text(location, 200)) {
      return res.status(400).json({ error: 'Select the facility where this physical update is taking place.' });
    }
    if (CONFIRMATION_STATUSES.has(status) && confirmed !== true) {
      return res.status(400).json({ error: 'Confirm that you have physically verified this shipment at the selected facility.' });
    }
    if (releasedToName != null && (typeof releasedToName !== 'string' || releasedToName.length > 120)) {
      return res.status(400).json({ error: 'Enter the name of the person receiving the parcel (up to 120 characters).' });
    }
    if (releasedToIdNumber != null && (typeof releasedToIdNumber !== 'string' || releasedToIdNumber.length > 80)) {
      return res.status(400).json({ error: 'Enter the handover ID or reference (up to 80 characters).' });
    }
    if (deliveredToName != null && (typeof deliveredToName !== 'string' || deliveredToName.length > 120)) {
      return res.status(400).json({ error: 'Enter the recipient name (up to 120 characters).' });
    }
    if (deliveredToIdNumber != null && (typeof deliveredToIdNumber !== 'string' || deliveredToIdNumber.length > 80)) {
      return res.status(400).json({ error: 'Enter the recipient ID or reference (up to 80 characters).' });
    }
    if (deliveryProofType != null && !DELIVERY_PROOF_TYPES.includes(deliveryProofType)) {
      return res.status(400).json({ error: `deliveryProofType must be one of ${DELIVERY_PROOF_TYPES.join(', ')}` });
    }
    if (deliveryProofReference != null && (typeof deliveryProofReference !== 'string' || deliveryProofReference.length > 300)) {
      return res.status(400).json({ error: 'Proof reference must be at most 300 characters.' });
    }

    const event = await prisma.$transaction(async (tx) => {
      await warehouseLock(tx, organizationId);
      const current = await tx.parcel.findUnique({ where: { id: parcel.id }, include: { container: true } });
      if (!current) fail(404, 'Parcel not found');
      if (current.container && current.container.status !== 'ARRIVED') {
        const conflict = new Error('This parcel is in a container. Record departure and arrival from the container workspace.');
        conflict.status = 409;
        throw conflict;
      }

      const facility = await resolveFacility(tx, organizationId, { locationId, location });
      if (PHYSICAL_STATUSES.has(status) && !facility) {
        fail(400, 'Select a valid D2F facility for this physical update.');
      }
      if (facility && !isFacilityAuthorized(req.user, facility)) {
        fail(403, facilityDeniedMessage(facility));
      }

      if (status === 'IN_TRANSIT') {
        if (current.locationId && current.locationId !== facility.id) {
          fail(409, 'Departure must be confirmed from the facility where the parcel is currently held.');
        }
      }
      if (status === 'ARRIVED_LOME' && !isLomeLocation(facility)) {
        fail(400, 'All international arrivals must first be received at the Lomé facility.');
      }
      if (status === 'ARRIVED_DESTINATION' && !destinationMatchesLocation(current.destination, facility)) {
        fail(400, `Choose the receiving facility for ${current.destination}. If the parcel has not been transferred there, record the transfer first.`);
      }
      if (status === 'READY_FOR_PICKUP') {
        if (current.locationId && current.locationId !== facility.id) {
          fail(409, 'Record the physical transfer and receiving confirmation before marking this parcel ready for pickup at another facility.');
        }
        if (!destinationMatchesLocation(current.destination, facility)) {
          fail(400, `This parcel is destined for ${current.destination}. It cannot be marked ready for pickup at ${locationLabel(facility)} without an authorized transfer.`);
        }
      }

      const data = { status, locationId: facility?.id ?? current.locationId };
      if (status === 'RELEASED') {
        if (!text(releasedToName, 120)) fail(400, 'Enter the name of the person receiving the parcel.');
        if (!text(releasedToIdNumber, 80)) fail(400, 'Record the handover ID or reference before releasing the parcel.');
        const when = validDate(releasedAt);
        if (!when) fail(400, 'Enter a valid handover date and time (not in the future).');
        data.releasedToName = releasedToName.trim();
        data.releasedToIdNumber = releasedToIdNumber.trim();
        data.releasedAt = when;
      }
      if (status === 'DELIVERED') {
        const recipient = text(deliveredToName, 120) ? deliveredToName.trim() : current.releasedToName;
        if (!recipient) fail(400, 'Enter the recipient name before confirming delivery.');
        const when = validDate(deliveredAt);
        if (!when) fail(400, 'Enter a valid delivery date and time (not in the future).');
        if (!deliveryProofType || !text(deliveryProofReference, 300)) {
          fail(400, 'Record proof of delivery (signature, photo, ID confirmation, or recipient confirmation) before marking the parcel delivered.');
        }
        if (deliveryProofType === 'ID_CONFIRMATION' && !text(deliveredToIdNumber, 80)) {
          fail(400, 'Record the recipient ID number for an ID-confirmed delivery.');
        }
        data.deliveredToName = recipient;
        data.deliveredToIdNumber = text(deliveredToIdNumber, 80) ? deliveredToIdNumber.trim() : current.releasedToIdNumber;
        data.deliveredAt = when;
        data.deliveryProofType = deliveryProofType;
        data.deliveryProofReference = deliveryProofReference.trim();
      }

      const updated = await tx.parcel.updateMany({
        where: { id: parcel.id, organizationId, status: parcel.status },
        data,
      });
      if (updated.count !== 1) {
        const conflict = new Error('The parcel was updated by another request. Refresh and try again.');
        conflict.status = 409;
        throw conflict;
      }
      const recorded = await tx.trackingEvent.create({
        data: {
          parcelId: parcel.id,
          status,
          note: note?.trim() || null,
          location: facility ? locationLabel(facility) : location?.trim() || null,
          actorId: req.user.id,
        },
      });
      await tx.auditLog.create({
        data: {
          actorId: req.user.id,
          action: 'PARCEL_STATUS_UPDATE',
          entity: 'Parcel',
          entityId: parcel.id,
          detail: `${parcel.status} → ${status}${facility ? ` @ ${locationLabel(facility)}` : ''}${status === 'DELIVERED' ? ` · proof=${deliveryProofType}` : ''}`,
        },
      });
      return recorded;
    });

    res.status(201).json(event);
  } catch (e) {
    next(e);
  }
});

// PATCH /parcels/:id/events/:eventId/note — correct an accidental note without
// deleting the event, actor, timestamp or location. Staff may correct their own
// note; administrators may correct any note in the organization.
router.patch('/:id/events/:eventId/note', requireRole('STAFF', 'ADMIN'), async (req, res, next) => {
  try {
    const organizationId = await resolveOrganizationId(prisma, req.user);
    const note = req.body?.note;
    if (note != null && (typeof note !== 'string' || note.length > 1000)) {
      return res.status(400).json({ error: 'The operational note must be at most 1,000 characters.' });
    }
    const result = await prisma.$transaction(async (tx) => {
      const parcel = await tx.parcel.findFirst({ where: { id: req.params.id, organizationId }, select: { id: true, trackingId: true } });
      if (!parcel) fail(404, 'Parcel not found.');
      const event = await tx.trackingEvent.findFirst({ where: { id: req.params.eventId, parcelId: parcel.id } });
      if (!event) fail(404, 'Tracking event not found.');
      if (req.user.role !== 'ADMIN' && event.actorId !== req.user.id) {
        fail(403, 'You can only correct notes you recorded yourself.');
      }
      const updated = await tx.trackingEvent.update({
        where: { id: event.id },
        data: { note: note?.trim() || null },
      });
      await tx.auditLog.create({
        data: {
          actorId: req.user.id,
          action: 'PARCEL_EVENT_NOTE_EDIT',
          entity: 'Parcel',
          entityId: parcel.id,
          detail: JSON.stringify({ trackingId: parcel.trackingId, eventId: event.id, from: event.note, to: updated.note }),
        },
      });
      return updated;
    });
    res.json(result);
  } catch (e) {
    next(e);
  }
});

// POST /parcels/:id/transfers — record a facility-to-facility movement after
// arrival. The receiving facility becomes the parcel's current location.
router.post('/:id/transfers', requireRole('STAFF', 'ADMIN'), async (req, res, next) => {
  try {
    const organizationId = await resolveOrganizationId(prisma, req.user);
    const { toLocationId, note } = req.body || {};
    if (!text(toLocationId, 80)) return res.status(400).json({ error: 'Choose the receiving facility.' });
    if (note != null && (typeof note !== 'string' || note.length > 1000)) {
      return res.status(400).json({ error: 'The transfer note must be at most 1,000 characters.' });
    }
    const result = await prisma.$transaction(async (tx) => {
      await warehouseLock(tx, organizationId);
      const parcel = await tx.parcel.findFirst({
        where: { id: req.params.id, organizationId },
        include: { location: true, container: true },
      });
      if (!parcel) fail(404, 'Parcel not found.');
      if (!['ARRIVED_LOME', 'ARRIVED_DESTINATION'].includes(parcel.status)) {
        fail(409, 'A parcel can only be transferred after it has been received at a facility.');
      }
      if (parcel.container && parcel.container.status !== 'ARRIVED') {
        fail(409, 'Record container arrival before transferring this parcel.');
      }
      const toLocation = await tx.location.findFirst({ where: { id: toLocationId, organizationId } });
      if (!toLocation) fail(400, 'Choose a receiving facility in your organization.');
      if (parcel.locationId === toLocation.id) fail(409, 'The parcel is already at this facility.');
      if (!parcel.location || !isFacilityAuthorized(req.user, parcel.location)) {
        fail(403, 'Only staff at the current facility or an administrator can release this parcel for transfer.');
      }
      const destinationReached = destinationMatchesLocation(parcel.destination, toLocation);
      const nextStatus = destinationReached ? 'ARRIVED_DESTINATION' : parcel.status;
      const updated = await tx.parcel.update({
        where: { id: parcel.id },
        data: { locationId: toLocation.id, status: nextStatus },
      });
      const fromLabel = locationLabel(parcel.location);
      const toLabel = locationLabel(toLocation);
      await tx.parcelTransfer.create({
        data: {
          parcelId: parcel.id,
          fromLocationId: parcel.locationId,
          toLocationId: toLocation.id,
          actorId: req.user.id,
          note: note?.trim() || null,
        },
      });
      await tx.trackingEvent.create({
        data: {
          parcelId: parcel.id,
          status: 'TRANSFERRED',
          note: note?.trim() || `Transferred from ${fromLabel} to ${toLabel}`,
          location: toLabel,
          actorId: req.user.id,
        },
      });
      await tx.auditLog.create({
        data: {
          actorId: req.user.id,
          action: 'PARCEL_TRANSFER',
          entity: 'Parcel',
          entityId: parcel.id,
          detail: `${fromLabel} → ${toLabel}${destinationReached ? ' (destination reached)' : ''}`,
        },
      });
      return updated;
    });
    res.status(201).json(result);
  } catch (e) {
    next(e);
  }
});

// PATCH /parcels/:id — correct intake details without rewriting tracking history.
router.patch('/:id', requireRole('ADMIN'), async (req, res, next) => {
  try {
    const body = req.body;
    const fields = ['customerId', 'recipientName', 'recipientPhone', 'recipientAddress', 'pickupAddress', 'packageType', 'weightKg', 'origin', 'destination', 'method', 'notes'];
    if (!body || Array.isArray(body) || typeof body !== 'object' || Object.keys(body).some(key => ![...fields, 'updatedAt'].includes(key))) {
      return res.status(400).json({ error: 'Only parcel input details can be edited.' });
    }
    if (typeof body.updatedAt !== 'string' || !Number.isFinite(Date.parse(body.updatedAt))) {
      return res.status(400).json({ error: 'Reload the parcel before editing (updatedAt is required).' });
    }
    const data = {};
    const textLimits = { customerId: 120, recipientName: 120, recipientPhone: 80, recipientAddress: 1000, pickupAddress: 1000, origin: 120, destination: 120, notes: 1000 };
    const optional = ['recipientPhone', 'recipientAddress', 'pickupAddress', 'notes'];
    for (const field of fields) {
      if (!Object.hasOwn(body, field)) continue;
      const value = body[field];
      if (field in textLimits) {
        if (optional.includes(field) && value === null) { data[field] = null; continue; }
        if (typeof value !== 'string' || value.trim().length > textLimits[field] || (!optional.includes(field) && !value.trim())) {
          return res.status(400).json({ error: `Invalid ${field}.` });
        }
        data[field] = value.trim() || null;
      } else if (field === 'weightKg') {
        if (!['number', 'string'].includes(typeof value) || !Number.isFinite(Number(value)) || Number(value) <= 0 || Number(value) > 10000) {
          return res.status(400).json({ error: 'Weight must be greater than zero and at most 10,000 kg.' });
        }
        data[field] = Number(value);
      } else {
        const choices = field === 'method' ? METHODS : PACKAGE_TYPES;
        if (!choices.includes(value)) return res.status(400).json({ error: `${field} must be one of ${choices.join(', ')}` });
        data[field] = value;
      }
    }
    if (!Object.keys(data).length) return res.status(400).json({ error: 'Provide at least one parcel detail to edit.' });
    const organizationId = await resolveOrganizationId(prisma, req.user);
    const parcel = await prisma.$transaction(async tx => {
      await warehouseLock(tx, organizationId);
      const current = await tx.parcel.findFirst({ where: { id: req.params.id, organizationId }, include: { container: true } });
      if (!current) fail(404, 'Parcel not found');
      if (current.updatedAt.getTime() !== Date.parse(body.updatedAt)) fail(409, 'This parcel has changed. Close the form and refresh the parcel before editing again.');
      if (data.customerId && data.customerId !== current.customerId) {
        const customer = await tx.customer.findFirst({ where: { id: data.customerId, organizationId } });
        if (!customer) fail(404, 'Customer not found');
        // Linked shopping orders must continue to belong to the same customer.
        if (await tx.serviceOrder.count({ where: { parcelId: current.id } })) fail(409, 'This parcel is linked to a shopping order. Its customer cannot be changed.');
      }
      const changes = Object.fromEntries(Object.entries(data).filter(([field, value]) => current[field] !== value));
      if (current.container && current.container.status !== 'ARRIVED' && ['origin', 'destination', 'method'].some(field => field in changes)) {
        fail(409, 'Remove this parcel from its loading container before changing its route or shipping method. Departed containers must arrive first.');
      }
      const routeFields = ['origin', 'destination', 'method', 'pickupAddress', 'recipientAddress'];
      if (routeFields.some(field => field in changes)) {
        const routeError = validateRoute({
          origin: changes.origin ?? current.origin,
          destination: changes.destination ?? current.destination,
          method: changes.method ?? current.method,
          pickupAddress: changes.pickupAddress ?? current.pickupAddress,
          recipientAddress: changes.recipientAddress ?? current.recipientAddress,
        });
        if (routeError) fail(400, routeError);
      }
      if (Object.keys(changes).length) {
        const updated = await tx.parcel.updateMany({
          where: { id: current.id, organizationId, updatedAt: new Date(body.updatedAt) },
          data: { ...changes, updatedAt: new Date(Math.max(Date.now(), current.updatedAt.getTime() + 1)) },
        });
        if (updated.count !== 1) fail(409, 'This parcel has changed. Refresh it before editing again.');
        await tx.auditLog.create({ data: {
          actorId: req.user.id, action: 'PARCEL_EDIT', entity: 'Parcel', entityId: current.id,
          detail: JSON.stringify({ trackingId: current.trackingId, changes: Object.fromEntries(Object.entries(changes).map(([field, value]) => [field, { from: current[field], to: value }])) }),
        } });
      }
      return tx.parcel.findUnique({ where: { id: current.id }, include: parcelInclude });
    });
    res.json(parcel);
  } catch (error) { next(error); }
});

// GET /parcels/:idOrTracking — detail incl. event history
router.get('/:idOrTracking', async (req, res, next) => {
  try {
    const { idOrTracking } = req.params;
    const organizationId = await resolveOrganizationId(prisma, req.user);

    let parcel = await prisma.parcel.findFirst({
      where: { id: idOrTracking, organizationId },
      include: parcelInclude,
    });

    if (!parcel) {
      parcel = await prisma.parcel.findFirst({
        where: { trackingId: idOrTracking.toUpperCase(), organizationId },
        include: parcelInclude,
      });
    }

    if (!parcel) return res.status(404).json({ error: 'Parcel not found' });
    res.json(parcel);
  } catch (e) {
    next(e);
  }
});

export default router;
