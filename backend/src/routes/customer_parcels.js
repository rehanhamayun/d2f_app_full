import { Router } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { generateTrackingId } from '../tracking.js';

const router = Router();
const packageTypes = [
  'BOX',
  'BARREL',
  'TV',
  'APPLIANCE',
  'FURNITURE',
  'PALLET',
  'VEHICLE',
  'DOCUMENTS',
  'OTHER',
];
const methods = ['AIR', 'SEA', 'ROAD'];
const parcelSelect = {
  id: true,
  trackingId: true,
  customerId: true,
  recipientName: true,
  recipientPhone: true,
  recipientAddress: true,
  packageType: true,
  weightKg: true,
  origin: true,
  destination: true,
  method: true,
  status: true,
  createdAt: true,
  updatedAt: true,
  events: {
    select: { id: true, status: true, createdAt: true },
    orderBy: { createdAt: 'asc' },
  },
};

router.use(authenticate, requireRole('CUSTOMER'));

router.get('/', async (req, res, next) => {
  try {
    const customer = await prisma.customer.findUnique({
      where: { userId: req.user.id },
      select: { id: true },
    });
    if (!customer) return res.json([]);

    const parcels = await prisma.parcel.findMany({
      where: { customerId: customer.id },
      orderBy: { createdAt: 'desc' },
      take: 100,
      select: parcelSelect,
    });
    res.json(parcels);
  } catch (error) {
    next(error);
  }
});

router.post('/', async (req, res, next) => {
  try {
    const {
      recipientName,
      recipientPhone,
      recipientAddress,
      packageType,
      weightKg,
      origin,
      destination,
      method = 'AIR',
      notes,
      clientRequestId,
    } = req.body || {};

    if (
      typeof recipientName !== 'string' ||
      !recipientName.trim() ||
      recipientName.trim().length > 120
    ) {
      return res.status(400).json({ error: 'Enter a recipient name up to 120 characters.' });
    }
    if (
      recipientPhone != null &&
      (typeof recipientPhone !== 'string' || recipientPhone.length > 40)
    ) {
      return res.status(400).json({ error: 'Enter a valid recipient phone number.' });
    }
    if (
      recipientAddress != null &&
      (typeof recipientAddress !== 'string' || recipientAddress.length > 500)
    ) {
      return res.status(400).json({ error: 'Recipient address must be at most 500 characters.' });
    }
    if (!packageTypes.includes(packageType)) {
      return res.status(400).json({ error: 'Choose a valid package type.' });
    }
    if (
      typeof weightKg !== 'number' ||
      !Number.isFinite(weightKg) ||
      weightKg <= 0 ||
      weightKg > 10000
    ) {
      return res.status(400).json({ error: 'Enter a weight greater than 0 and at most 10,000 kg.' });
    }
    if (typeof origin !== 'string' || !origin.trim() || origin.trim().length > 120) {
      return res.status(400).json({ error: 'Enter an origin up to 120 characters.' });
    }
    if (
      typeof destination !== 'string' ||
      !destination.trim() ||
      destination.trim().length > 120
    ) {
      return res.status(400).json({ error: 'Enter a destination up to 120 characters.' });
    }
    if (!methods.includes(method)) {
      return res.status(400).json({ error: 'Choose a valid shipping method.' });
    }
    if (notes != null && (typeof notes !== 'string' || notes.length > 1000)) {
      return res.status(400).json({ error: 'Shipment notes must be at most 1,000 characters.' });
    }
    if (
      clientRequestId != null &&
      (typeof clientRequestId !== 'string' ||
        !clientRequestId.trim() ||
        clientRequestId.length > 120)
    ) {
      return res.status(400).json({ error: 'Invalid request identifier.' });
    }

    let createdNew = true;
    const parcel = await prisma.$transaction(async (tx) => {
      const customer = await tx.customer.upsert({
        where: { userId: req.user.id },
        update: {
          displayName: req.user.fullName,
          email: req.user.email,
          phone: req.user.phone,
        },
        create: {
          userId: req.user.id,
          displayName: req.user.fullName,
          email: req.user.email,
          phone: req.user.phone,
        },
      });

      const trackingId = await generateTrackingId(tx);
      if (clientRequestId) {
        const existing = await tx.parcel.findUnique({
          where: { clientRequestId },
          include: { customer: { select: { userId: true } } },
        });
        if (existing) {
          if (existing.customer.userId !== req.user.id) {
            const conflict = new Error('This request identifier has already been used.');
            conflict.status = 409;
            throw conflict;
          }
          createdNew = false;
          return tx.parcel.findUniqueOrThrow({
            where: { id: existing.id },
            select: parcelSelect,
          });
        }
      }

      const created = await tx.parcel.create({
        data: {
          trackingId,
          customerId: customer.id,
          recipientName: recipientName.trim(),
          recipientPhone: recipientPhone?.trim() || null,
          recipientAddress: recipientAddress?.trim() || null,
          packageType,
          weightKg,
          origin: origin.trim(),
          destination: destination.trim(),
          method,
          notes: notes?.trim() || null,
          status: 'REQUESTED',
          createdById: req.user.id,
          clientRequestId: clientRequestId || null,
        },
      });

      await tx.trackingIndex.create({
        data: { trackingId, parcelId: created.id },
      });
      await tx.trackingEvent.create({
        data: {
          parcelId: created.id,
          status: 'REQUESTED',
          note: 'Shipment request submitted by customer',
          location: origin.trim(),
          actorId: req.user.id,
        },
      });
      await tx.auditLog.create({
        data: {
          actorId: req.user.id,
          action: 'CUSTOMER_PARCEL_REQUEST',
          entity: 'Parcel',
          entityId: created.id,
          detail: `trackingId=${trackingId}`,
        },
      });

      return tx.parcel.findUniqueOrThrow({
        where: { id: created.id },
        select: parcelSelect,
      });
    });

    res.status(createdNew ? 201 : 200).json(parcel);
  } catch (error) {
    next(error);
  }
});

export default router;
