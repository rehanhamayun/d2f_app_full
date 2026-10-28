import { Router, raw } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { EDITABLE_REQUEST_STATUSES, validFutureDate } from '../parcel_rules.js';
import { generateTrackingId, resolveOrganizationId } from '../tracking.js';

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
const deliveryModes = ['PICKUP', 'DROP_OFF'];

// Customer shipment requests list their goods item by item. Up to 20 items
// per shipment keeps the intake sheet usable; quantities stay per item.
const MAX_ITEMS = 20;

// Photos of the goods. Stored in the database as bytes so the evidence
// gallery survives redeploys without external object storage.
const IMAGE_CONTENT_TYPES = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};
const MAX_IMAGE_BYTES = 4 * 1024 * 1024; // 4 MB after client-side compression
const MAX_IMAGES_PER_PARCEL = 8;

const parcelSelect = {
  id: true,
  trackingId: true,
  customerId: true,
  recipientName: true,
  recipientPhone: true,
  recipientAddress: true,
  pickupAddress: true,
  packageType: true,
  weightKg: true,
  origin: true,
  destination: true,
  method: true,
  notes: true,
  deliveryMode: true,
  pickupScheduledAt: true,
  status: true,
  createdAt: true,
  updatedAt: true,
  items: {
    select: {
      id: true,
      name: true,
      details: true,
      quantity: true,
      weightKg: true,
      position: true,
    },
    orderBy: [{ position: 'asc' }, { createdAt: 'asc' }],
  },
  images: {
    select: {
      id: true,
      fileName: true,
      contentType: true,
      sizeBytes: true,
      createdAt: true,
    },
    orderBy: { createdAt: 'asc' },
  },
  events: {
    select: { id: true, status: true, note: true, createdAt: true },
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

/**
 * Validates one requested goods entry. Returns { error } for a bad item or
 * { value } with the trimmed/normalized item for a good one.
 */
function normalizeItem(rawItem, index) {
  if (!rawItem || typeof rawItem !== 'object' || Array.isArray(rawItem)) {
    return { error: `Item ${index + 1}: enter the item description.` };
  }
  const name = typeof rawItem.name === 'string' ? rawItem.name.trim() : '';
  if (!name || name.length > 120) {
    return {
      error: `Item ${index + 1}: describe the goods in up to 120 characters.`,
    };
  }
  const quantity = rawItem.quantity == null ? 1 : Number(rawItem.quantity);
  if (
    !Number.isSafeInteger(quantity) ||
    quantity < 1 ||
    quantity > 999
  ) {
    return {
      error: `Item ${index + 1}: quantity must be a whole number between 1 and 999.`,
    };
  }
  let weightKg = null;
  if (rawItem.weightKg != null) {
    weightKg = Number(rawItem.weightKg);
    if (
      !Number.isFinite(weightKg) ||
      weightKg <= 0 ||
      weightKg > 1000
    ) {
      return {
        error: `Item ${index + 1}: weight must be between 0 and 1,000 kg.`,
      };
    }
    weightKg = Math.round(weightKg * 100) / 100;
  }
  let details = null;
  if (rawItem.details != null) {
    if (typeof rawItem.details !== 'string' || rawItem.details.length > 300) {
      return {
        error: `Item ${index + 1}: item details must be at most 300 characters.`,
      };
    }
    details = rawItem.details.trim() || null;
  }
  return {
    value: { name, details, quantity, weightKg, position: index },
  };
}

const ownedParcel = (where, userId) =>
  prisma.parcel.findFirst({
    where: { ...where, customer: { userId } },
    select: {
      id: true,
      customerId: true,
      status: true,
      deliveryMode: true,
    },
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
      pickupAddress,
      pickupScheduledAt,
      deliveryMode = 'DROP_OFF',
      items,
      clientRequestId,
    } = req.body || {};

    if (typeof req.user.phone !== 'string' || !req.user.phone.trim()) {
      return res.status(400).json({
        error:
          'Add your phone number in your profile before requesting a shipment. Our team needs it to reach you.',
      });
    }
    if (
      typeof recipientName !== 'string' ||
      !recipientName.trim() ||
      recipientName.trim().length > 120
    ) {
      return res.status(400).json({ error: 'Enter a recipient name up to 120 characters.' });
    }
    if (
      typeof recipientPhone !== 'string' ||
      recipientPhone.trim().length < 6 ||
      recipientPhone.trim().length > 40
    ) {
      return res
        .status(400)
        .json({ error: 'Enter the recipient phone number (6 to 40 characters).' });
    }
    if (
      typeof recipientAddress !== 'string' ||
      !recipientAddress.trim() ||
      recipientAddress.length > 500
    ) {
      return res.status(400).json({
        error: 'Enter the delivery address (it is required so our team can see where goods are going).',
      });
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
    if (!deliveryModes.includes(deliveryMode)) {
      return res
        .status(400)
        .json({ error: 'Choose how goods reach D2F: warehouse drop-off or pickup.' });
    }

    // Collection details are compulsory for pickups: the address tells the
    // driver where to come, the slot tells them when the customer expects it.
    let scheduledPickup = null;
    if (deliveryMode === 'PICKUP') {
      if (
        typeof pickupAddress !== 'string' ||
        !pickupAddress.trim() ||
        pickupAddress.trim().length > 500
      ) {
        return res.status(400).json({
          error:
            'Enter the collection address so our team knows where to pick up your goods.',
        });
      }
      const when = validFutureDate(pickupScheduledAt);
      if (!when) {
        return res.status(400).json({
          error:
            'Choose a pickup date and time at least one hour from now (within 90 days).',
        });
      }
      scheduledPickup = when;
    } else if (pickupAddress != null) {
      if (typeof pickupAddress !== 'string' || pickupAddress.trim().length > 500) {
        return res
          .status(400)
          .json({ error: 'Collection address must be at most 500 characters.' });
      }
    }

    if (
      clientRequestId != null &&
      (typeof clientRequestId !== 'string' ||
        !clientRequestId.trim() ||
        clientRequestId.length > 120)
    ) {
      return res.status(400).json({ error: 'Invalid request identifier.' });
    }

    // Goods list: optional (legacy single-package requests are still valid),
    // but every entry must be complete. The app always sends at least one item.
    let normalizedItems = [];
    if (items != null) {
      if (!Array.isArray(items) || items.length > MAX_ITEMS) {
        return res.status(400).json({
          error: `This shipment can list up to ${MAX_ITEMS} items. Describe each thing you are sending.`,
        });
      }
      for (let index = 0; index < items.length; index += 1) {
        const normalized = normalizeItem(items[index], index);
        if (normalized.error) return res.status(400).json({ error: normalized.error });
        normalizedItems.push(normalized.value);
      }
    }

    let createdNew = true;
    const parcel = await prisma.$transaction(async (tx) => {
      const linkedCustomer = await tx.customer.findUnique({
        where: { userId: req.user.id },
        select: { organizationId: true },
      });
      const organizationId = await resolveOrganizationId(tx, {
        ...req.user,
        organizationId: req.user.organizationId || linkedCustomer?.organizationId,
      });
      const customer = await tx.customer.upsert({
        where: { userId: req.user.id },
        update: {
          organizationId,
          displayName: req.user.fullName,
          email: req.user.email,
          phone: req.user.phone,
        },
        create: {
          userId: req.user.id,
          organizationId,
          displayName: req.user.fullName,
          email: req.user.email,
          phone: req.user.phone,
        },
      });

      if (clientRequestId) {
        await tx.$executeRaw`
          SELECT pg_advisory_xact_lock(hashtextextended(${`${organizationId}:${clientRequestId}`}, 0))
        `;
        const existing = await tx.parcel.findUnique({
          where: { organizationId_clientRequestId: { organizationId, clientRequestId } },
          include: { customer: { select: { userId: true } } },
        });
        if (existing) {
          if (
            existing.customer.userId !== req.user.id ||
            existing.organizationId !== organizationId
          ) {
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

      const tracking = await generateTrackingId(tx, organizationId);
      const collectionNote =
        deliveryMode === 'PICKUP'
          ? 'Shipment request submitted by customer · goods collection requested.'
          : 'Shipment request submitted by customer · goods brought to the warehouse.';
      const created = await tx.parcel.create({
        data: {
          ...tracking,
          customerId: customer.id,
          recipientName: recipientName.trim(),
          recipientPhone: recipientPhone.trim(),
          recipientAddress: recipientAddress.trim(),
          packageType,
          weightKg,
          origin: origin.trim(),
          destination: destination.trim(),
          method,
          notes: notes?.trim() || null,
          deliveryMode,
          pickupAddress: deliveryMode === 'PICKUP' ? pickupAddress.trim() : pickupAddress?.trim() || null,
          pickupScheduledAt: scheduledPickup,
          status: 'REQUESTED',
          createdById: req.user.id,
          clientRequestId: clientRequestId || null,
        },
      });

      if (normalizedItems.length) {
        await tx.parcelItem.createMany({
          data: normalizedItems.map((item) => ({ ...item, parcelId: created.id })),
        });
      }

      await tx.trackingIndex.create({
        data: { trackingId: tracking.trackingId, parcelId: created.id },
      });
      await tx.trackingEvent.create({
        data: {
          parcelId: created.id,
          status: 'REQUESTED',
          note: collectionNote,
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
          detail: `trackingId=${tracking.trackingId} mode=${deliveryMode}${deliveryMode === 'PICKUP' ? ` · pickup=${scheduledPickup.toISOString()}` : ''}`,
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

// ── Goods photos (optional attachment) ───────────────────────────────────────
// Bytes ride in the request body with the image content type; metadata travels
// as query parameters to avoid header-encoding surprises on every runtime.

router.get('/:parcelId/images', async (req, res, next) => {
  try {
    const parcel = await ownedParcel(
      { id: req.params.parcelId },
      req.user.id,
    );
    if (!parcel) return res.status(404).json({ error: 'Shipment not found.' });
    const images = await prisma.parcelImage.findMany({
      where: { parcelId: parcel.id },
      select: { id: true, fileName: true, contentType: true, sizeBytes: true, createdAt: true },
      orderBy: { createdAt: 'asc' },
    });
    res.json(images);
  } catch (error) {
    next(error);
  }
});

router.post('/:parcelId/images', raw({ type: Object.keys(IMAGE_CONTENT_TYPES), limit: MAX_IMAGE_BYTES }), async (req, res, next) => {
  try {
    // Shipping requests freeze at warehouse intake: after staff have verified
    // the goods in person, the photo record stops changing.
    const parcel = await ownedParcel({ id: req.params.parcelId }, req.user.id);
    if (!parcel) return res.status(404).json({ error: 'Shipment not found.' });
    if (parcel.status && !EDITABLE_REQUEST_STATUSES.has(parcel.status)) {
      return res.status(409).json({
        error: 'Parcel has been received and verified; goods photos can no longer be changed.',
      });
    }

    const extension = IMAGE_CONTENT_TYPES[req.headers['content-type']];
    if (!extension || !Buffer.isBuffer(req.body) || req.body.length < 16) {
      return res.status(415).json({
        error: 'Attach a JPEG, PNG or WebP photo of the goods.',
      });
    }
    if (req.body.length > MAX_IMAGE_BYTES) {
      return res
        .status(413)
        .json({ error: 'That photo is larger than 4 MB. Please retry after compressing it.' });
    }

    const count = await prisma.parcelImage.count({ where: { parcelId: parcel.id } });
    if (count >= MAX_IMAGES_PER_PARCEL) {
      return res.status(409).json({
        error: `A shipment can hold at most ${MAX_IMAGES_PER_PARCEL} photos of the goods.`,
      });
    }

    const label = validImageLabel(req.query.label?.toString());
    const fileName = validImageFileName(req.query.name?.toString(), extension);

    const image = await prisma.parcelImage.create({
      data: {
        parcelId: parcel.id,
        fileName,
        contentType: req.headers['content-type'],
        sizeBytes: req.body.length,
        bytes: req.body,
        uploadedById: req.user.id,
      },
      select: { id: true, fileName: true, contentType: true, sizeBytes: true, createdAt: true },
    });
    await prisma.auditLog.create({
      data: {
        actorId: req.user.id,
        action: 'PARCEL_IMAGE_UPLOAD',
        entity: 'Parcel',
        entityId: parcel.id,
        detail: `image=${image.fileName} bytes=${image.sizeBytes}${label ? ` label=${label}` : ''}`,
      },
    });
    res.status(201).json(image);
  } catch (error) {
    // Request bodies above the express.raw limit report as entity-too-large
    // errors that carry no status for us to reuse; normalize the response.
    if (error?.type === 'entity.too.large' || error?.statusCode === 413) {
      return res
        .status(413)
        .json({ error: 'That photo is larger than 4 MB. Please retry after compressing it.' });
    }
    next(error);
  }
});

router.get('/:parcelId/images/:imageId/raw', async (req, res, next) => {
  try {
    const parcel = await ownedParcel({ id: req.params.parcelId }, req.user.id);
    if (!parcel) return res.status(404).json({ error: 'Shipment not found.' });
    const image = await prisma.parcelImage.findFirst({
      where: { id: req.params.imageId, parcelId: parcel.id },
    });
    if (!image) return res.status(404).json({ error: 'Photo not found.' });
    res.set({
      'Content-Type': image.contentType,
      'Content-Length': String(image.sizeBytes),
      'Cache-Control': 'private, max-age=300',
    });
    res.send(Buffer.from(image.bytes));
  } catch (error) {
    next(error);
  }
});

router.delete('/:parcelId/images/:imageId', async (req, res, next) => {
  try {
    const parcel = await ownedParcel({ id: req.params.parcelId }, req.user.id);
    if (!parcel) return res.status(404).json({ error: 'Shipment not found.' });
    if (parcel.status && !EDITABLE_REQUEST_STATUSES.has(parcel.status)) {
      return res.status(409).json({
        error: 'Parcel has been received and verified; goods photos can no longer be changed.',
      });
    }
    const removed = await prisma.parcelImage.deleteMany({
      where: { id: req.params.imageId, parcelId: parcel.id },
    });
    if (removed.count !== 1) return res.status(404).json({ error: 'Photo not found.' });
    await prisma.auditLog.create({
      data: {
        actorId: req.user.id,
        action: 'PARCEL_IMAGE_DELETE',
        entity: 'Parcel',
        entityId: parcel.id,
        detail: `imageId=${req.params.imageId}`,
      },
    });
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

function validImageLabel(value) {  if (!value) return null;
  const clean = value.trim();
  return clean && clean.length <= 120 ? clean : null;
}

function validImageFileName(value, extension) {
  const base = typeof value === 'string' ? value.trim() : '';
  const safe = base.replace(/[^\w.\- ]+/g, '_').replace(/^\.+/, '').slice(0, 100);
  return safe || `goods.${extension}`;
}

export default router;
