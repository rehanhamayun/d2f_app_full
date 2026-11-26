// Ship For Me — customer purchases themselves, D2F receives & ships.
// Customer uses their own card at retailers; D2F provides warehouse address,
// receives package, quotes shipping, then forwards to customer.
import { Router } from 'express';
import { createHash } from 'node:crypto';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { fail, warehouseLock } from '../warehouse.js';
import { audit, upsertCustomer, validAmount, validOptionalText, validText, currencies } from '../shopfront.js';
import { resolveOrganizationId } from '../tracking.js';
import { createNotification } from '../notifications.js';

const activeTerms = () => ({ serviceType: 'SHIP_FOR_ME', isActive: true, effectiveFrom: { lte: new Date() } });

const router = Router();
router.use(authenticate, requireRole('CUSTOMER'));

async function warehouseReference(tx, customer, userId) {
  const previous = customer && await tx.shipForMeRequest.findFirst({
    where: { customerId: customer.id, organizationId: customer.organizationId },
    orderBy: [{ createdAt: 'asc' }, { id: 'asc' }], select: { customerWarehouseId: true },
  });
  return previous?.customerWarehouseId || `D2F-${createHash('sha256').update(userId).digest('hex').slice(0, 14).toUpperCase()}`;
}

const requestSelect = {
  id: true,
  customerId: true,
  organizationId: true,
  warehouseAddressId: true,
  customerWarehouseId: true,
  retailerName: true,
  retailerOrderId: true,
  retailerTrackingId: true,
  itemDescription: true,
  declaredValueMinor: true,
  declaredCurrency: true,
  packageWeightKg: true,
  packageLengthCm: true,
  packageWidthCm: true,
  packageHeightCm: true,
  packagePhotos: true,
  receivedAt: true,
  receivedBy: true,
  packageCondition: true,
  receivingNotes: true,
  status: true,
  agreementAccepted: true,
  agreementVersion: true,
  acceptedAt: true,
  shippingFeeMinor: true,
  insuranceFeeMinor: true,
  handlingFeeMinor: true,
  totalQuoteMinor: true,
  quoteAcceptedAt: true,
  quoteValidUntil: true,
  quoteNotes: true,
  paymentStatus: true,
  paidAt: true,
  shippingMethod: true,
  carrier: true,
  carrierTrackingId: true,
  shippedAt: true,
  deliveredAt: true,
  createdAt: true,
  updatedAt: true,
  submittedAt: true,
};

// ── Get my Ship For Me requests ─────────────────────────────────────────

router.get('/requests', async (req, res, next) => {
  try {
    const customer = await prisma.customer.findUnique({
      where: { userId: req.user.id },
      select: { id: true },
    });
    if (!customer) return res.json([]);
    const requests = await prisma.shipForMeRequest.findMany({
      where: { customerId: customer.id },
      select: requestSelect,
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
    res.json(requests);
  } catch (error) {
    next(error);
  }
});

// ── Create a new Ship For Me request (draft) ────────────────────────────

router.post('/requests', async (req, res, next) => {
  try {
    const {
      retailerName, retailerOrderId, retailerTrackingId,
      itemDescription, declaredValueMinor, declaredCurrency = 'USD',
      notes,
    } = req.body || {};

    if (!validText(retailerName, 100)) fail(400, 'Enter the retailer name.');
    if (!validText(itemDescription, 500)) fail(400, 'Describe what you purchased.');
    if (!['USD', 'EUR', 'XOF'].includes(declaredCurrency)) fail(400, 'Choose a valid currency.');
    if (declaredValueMinor != null && !validAmount(declaredValueMinor)) {
      fail(400, 'Enter a valid declared value.');
    }

    const customer = await prisma.customer.findUnique({
      where: { userId: req.user.id },
      select: { id: true, organizationId: true },
    });
    if (!customer) fail(404, 'Customer profile not found.');

    const result = await prisma.$transaction(async tx => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended('customer-agreements', 0))`;
      await warehouseLock(tx, customer.organizationId);
      const latestAgreement = await tx.customerAgreement.findFirst({ where: activeTerms(), orderBy: { effectiveFrom: 'desc' } });
      if (!latestAgreement) fail(409, 'Ship For Me terms are awaiting publication. Contact D2F support.');
      const acceptance = await tx.customerAgreementAcceptance.findUnique({
        where: { customerId_agreementId: { customerId: customer.id, agreementId: latestAgreement.id } },
      });
      if (acceptance?.version !== latestAgreement.version) fail(403, 'Accept the current Ship For Me terms before registering a purchase.');
      const defaultAddress = await tx.warehouseAddress.findFirst({
        where: { organizationId: customer.organizationId, isActive: true, isDefault: true }, select: { id: true },
      });
      if (!defaultAddress) fail(409, 'D2F has not assigned a receiving address. Contact D2F support before shipping a purchase.');
      const customerWarehouseId = await warehouseReference(tx, customer, req.user.id);
      const created = await tx.shipForMeRequest.create({
        data: {
          organizationId: customer.organizationId,
          customerId: customer.id,
          warehouseAddressId: defaultAddress.id,
          customerWarehouseId,
          retailerName: retailerName.trim(),
          retailerOrderId: retailerOrderId?.trim() || null,
          retailerTrackingId: retailerTrackingId?.trim() || null,
          itemDescription: itemDescription.trim(),
          declaredValueMinor: declaredValueMinor ?? null,
          declaredCurrency,
          status: 'DRAFT',
          agreementAccepted: true,
          agreementVersion: latestAgreement.version,
          acceptedAt: acceptance.acceptedAt,
        },
        select: requestSelect,
      });
      await audit(tx, req, 'ShipForMeRequest', created.id, 'SHIP_FOR_ME_CREATE', created.retailerName);
      return created;
    });
    res.status(201).json(result);
  } catch (error) {
    next(error);
  }
});

// ── Submit retailer details (move DRAFT -> SUBMITTED) ───────────────────

router.post('/requests/:id/submit', async (req, res, next) => {
  try {
    const { retailerOrderId, retailerTrackingId } = req.body || {};
    const result = await prisma.$transaction(async (tx) => {
      const customer = await tx.customer.findUnique({
        where: { userId: req.user.id },
        select: { id: true },
      });
      if (!customer) fail(404, 'Request not found.');
      const existing = await tx.shipForMeRequest.findFirst({
        where: { id: req.params.id, customerId: customer.id },
      });
      if (!existing) fail(404, 'Request not found.');
      if (existing.status !== 'DRAFT') fail(409, 'Request already submitted or in progress.');
      const updated = await tx.shipForMeRequest.update({
        where: { id: existing.id },
        data: {
          status: 'SUBMITTED',
          submittedAt: new Date(),
          ...(retailerOrderId != null && { retailerOrderId: retailerOrderId.trim() || null }),
          ...(retailerTrackingId != null && { retailerTrackingId: retailerTrackingId.trim() || null }),
        },
        select: requestSelect,
      });
      await audit(tx, req, 'ShipForMeRequest', existing.id, 'SHIP_FOR_ME_SUBMIT', 'submitted retailer details');
      return updated;
    });
    res.json(result);
  } catch (error) {
    next(error);
  }
});

// ── Get warehouse address for customer ──────────────────────────────────

router.get('/warehouse-address', async (req, res, next) => {
  try {
    const customer = await prisma.customer.findUnique({
      where: { userId: req.user.id },
      select: { id: true, organizationId: true },
    });
    const organizationId = await resolveOrganizationId(prisma, { ...req.user, organizationId: req.user.organizationId || customer?.organizationId });
    const address = await prisma.warehouseAddress.findFirst({
      where: { organizationId, isActive: true, isDefault: true },
    });
    if (!address) fail(404, 'No warehouse address configured.');
    res.json({ ...address, customerWarehouseId: await warehouseReference(prisma, customer, req.user.id) });
  } catch (error) {
    next(error);
  }
});

// ── Get active terms agreement ──────────────────────────────────────────

router.get('/terms', async (req, res, next) => {
  try {
    const agreement = await prisma.customerAgreement.findFirst({
      where: activeTerms(),
      orderBy: { effectiveFrom: 'desc' },
    });
    if (!agreement) return res.status(404).json({ error: 'Ship For Me terms are awaiting publication. Retry or contact D2F support.' });
    const acceptance = await prisma.customerAgreementAcceptance.findFirst({
      where: { agreementId: agreement.id, version: agreement.version, customer: { userId: req.user.id } },
      select: { acceptedAt: true },
    });
    res.json({
      accepted: Boolean(acceptance),

      id: agreement.id,
      version: agreement.version,
      title: agreement.title,
      content: agreement.content,
      effectiveFrom: agreement.effectiveFrom,
    });
  } catch (error) {
    next(error);
  }
});

// ── Accept terms ────────────────────────────────────────────────────────

router.post('/terms/accept', async (req, res, next) => {
  try {
    const { agreementId, version } = req.body || {};
    const acceptance = await prisma.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended('customer-agreements', 0))`;
      const agreement = await tx.customerAgreement.findFirst({ where: activeTerms(), orderBy: { effectiveFrom: 'desc' } });
      if (!agreement) fail(404, 'Ship For Me terms have not been published.');
      if (agreementId !== agreement.id || version !== agreement.version) fail(409, 'The terms have changed. Return and review the current version.');
      const customer = await upsertCustomer(tx, req.user);
      const key = { customerId_agreementId: { customerId: customer.id, agreementId: agreement.id } };
      const previous = await tx.customerAgreementAcceptance.findUnique({ where: key });
      if (previous?.version === version) return previous;
      const saved = await tx.customerAgreementAcceptance.upsert({
        where: {
          customerId_agreementId: {
            customerId: customer.id,
            agreementId: agreement.id,
          },
        },
        update: { version: agreement.version, acceptedAt: new Date() },
        create: {
          customerId: customer.id,
          agreementId: agreement.id,
          version: agreement.version,
          acceptedAt: new Date(),
        },
      });
      await audit(tx, req, 'CustomerAgreementAcceptance', agreement.id, 'SHIP_FOR_ME_TERMS_ACCEPT', agreement.version);
      return saved;
    });
    res.json({ ok: true, version: acceptance.version, acceptedAt: acceptance.acceptedAt });
  } catch (error) {
    next(error);
  }
});

router.post('/requests/:id/accept-quote', async (req, res, next) => {
  try {
    const result = await prisma.$transaction(async tx => {
      const scope = { id: req.params.id, customer: { userId: req.user.id } };
      const first = await tx.shipForMeRequest.findFirst({ where: scope, select: { organizationId: true } });
      if (!first) fail(404, 'Request not found.');
      await warehouseLock(tx, first.organizationId);
      const current = await tx.shipForMeRequest.findFirst({ where: scope, select: requestSelect });
      if (!current) fail(404, 'Request not found.');
      if (req.body?.totalMinor !== current.totalQuoteMinor) fail(409, 'The quote changed. Review the latest charges.');
      if (current.quoteAcceptedAt && ['ACCEPTED', 'PAID', 'SHIPPED', 'COMPLETED'].includes(current.status)) return current;
      if (current.status !== 'QUOTED' || current.totalQuoteMinor == null) fail(409, 'D2F has not issued a shipping quote.');
      if (current.quoteValidUntil && current.quoteValidUntil <= new Date()) fail(409, 'This shipping quote has expired. Contact D2F.');
      if (req.body?.updatedAt !== current.updatedAt.toISOString()) fail(409, 'The quote changed. Review the latest charges.');
      const updated = await tx.shipForMeRequest.update({
        where: { id: current.id }, data: { status: 'ACCEPTED', quoteAcceptedAt: new Date() }, select: requestSelect,
      });
      await audit(tx, req, 'ShipForMeRequest', current.id, 'SHIP_FOR_ME_QUOTE_ACCEPTED', JSON.stringify({
        totalMinor: current.totalQuoteMinor, currency: 'USD',
      }));
      return updated;
    });
    res.json(result);
  } catch (error) {
    next(error);
  }
});

// ── Cancel my request ───────────────────────────────────────────────────

router.post('/requests/:id/cancel', async (req, res, next) => {
  try {
    const result = await prisma.$transaction(async (tx) => {
      const customer = await tx.customer.findUnique({
        where: { userId: req.user.id },
        select: { id: true, organizationId: true },
      });
      if (!customer) fail(404, 'Request not found.');
      await warehouseLock(tx, customer.organizationId);
      const existing = await tx.shipForMeRequest.findFirst({
        where: { id: req.params.id, customerId: customer.id },
      });
      if (!existing) fail(404, 'Request not found.');
      if (!['DRAFT', 'SUBMITTED', 'RECEIVED', 'QUOTED'].includes(existing.status)) {
        fail(409, 'This request cannot be cancelled at this stage.');
      }
      const updated = await tx.shipForMeRequest.update({
        where: { id: existing.id },
        data: { status: 'CANCELLED' },
        select: requestSelect,
      });
      await audit(tx, req, 'ShipForMeRequest', existing.id, 'SHIP_FOR_ME_CANCEL', 'cancelled by customer');
      return updated;
    });
    res.json(result);
  } catch (error) {
    next(error);
  }
});

export default router;
