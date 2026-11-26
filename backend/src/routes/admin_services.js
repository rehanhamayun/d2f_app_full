// Admin routes for Buy For Me / Ship For Me service configuration.
// Mounted at /admin/commerce/services
import { Router } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { fail, warehouseLock } from '../warehouse.js';
import { audit, validAmount, validOptionalText, validText, currencies } from '../shopfront.js';
import { createNotification } from '../notifications.js';
import { defaultRetailers, validRetailerUrl } from '../retailers.js';
import { resolveOrganizationId } from '../tracking.js';

const router = Router();
router.use(authenticate, requireRole('ADMIN'), async (req, res, next) => {
  try { req.organizationId = await resolveOrganizationId(prisma, req.user); next(); } catch (e) { next(e); }
});

const warehouseQuoteStatuses = ['SUBMITTED', 'RECEIVED', 'QUOTED', 'ACCEPTED', 'PAID'];
const shipForMeQuoteSelect = {
  id: true, status: true, paymentStatus: true, itemDescription: true, retailerName: true,
  retailerTrackingId: true, customerWarehouseId: true, packageWeightKg: true, shippingMethod: true,
  shippingFeeMinor: true, handlingFeeMinor: true, insuranceFeeMinor: true, totalQuoteMinor: true,
  customer: { select: { displayName: true } },
};
router.get('/ship-for-me/quotes', async (req, res, next) => {
  try {
    res.json(await prisma.shipForMeRequest.findMany({
      where: { organizationId: req.organizationId, status: { in: warehouseQuoteStatuses } },
      select: shipForMeQuoteSelect, orderBy: [{ updatedAt: 'desc' }, { id: 'asc' }], take: 100,
    }));
  } catch (error) { next(error); }
});

router.put('/ship-for-me/quotes/:id', async (req, res, next) => {
  try {
    const { shippingFeeMinor, handlingFeeMinor, insuranceFeeMinor, weightKg, method, received } = req.body || {};
    const totalQuoteMinor = shippingFeeMinor + handlingFeeMinor + insuranceFeeMinor;
    if (![shippingFeeMinor, handlingFeeMinor, insuranceFeeMinor, totalQuoteMinor].every(validAmount) ||
        typeof weightKg !== 'number' || !Number.isFinite(weightKg) || weightKg <= 0 || weightKg > 10000 ||
        !['AIR', 'SEA', 'ROAD'].includes(method) || received !== true) {
      fail(400, 'Verify physical receipt and enter the measured weight, shipping method and itemized USD charges.');
    }
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const row = await tx.shipForMeRequest.findFirst({ where: { id: req.params.id, organizationId: req.organizationId } });
      if (!row) fail(404, 'Ship For Me request not found.');
      if (!['SUBMITTED', 'RECEIVED', 'QUOTED'].includes(row.status)) fail(409, 'The quote is locked after customer acceptance.');
      const saved = await tx.shipForMeRequest.update({
        where: { id: row.id },
        data: {
          status: 'QUOTED', receivedAt: row.receivedAt ?? new Date(), receivedBy: row.receivedBy ?? req.user.id,
          shippingFeeMinor, handlingFeeMinor, insuranceFeeMinor, totalQuoteMinor,
          shippingMethod: method, packageWeightKg: weightKg, quoteValidUntil: null,
        },
        select: shipForMeQuoteSelect,
      });
      await audit(tx, req, 'ShipForMeRequest', row.id, 'SHIP_FOR_ME_QUOTED', JSON.stringify({
        shippingFeeMinor, handlingFeeMinor, insuranceFeeMinor, totalQuoteMinor, weightKg, method,
      }));
      return saved;
    });
    res.json(result);
  } catch (error) { next(error); }
});

router.post('/ship-for-me/quotes/:id/payment', async (req, res, next) => {
  try {
    const { reference, amountMinor } = req.body || {};
    if (!validText(reference, 120) || !validAmount(amountMinor)) fail(400, 'Enter the verified payment reference and amount.');
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const row = await tx.shipForMeRequest.findFirst({ where: { id: req.params.id, organizationId: req.organizationId } });
      if (!row) fail(404, 'Ship For Me request not found.');
      if (!['ACCEPTED', 'PAID'].includes(row.status) || row.totalQuoteMinor !== amountMinor) fail(409, 'Payment must match the accepted shipping quote.');
      const existing = await tx.payment.findFirst({
        where: { organizationId: req.organizationId, providerReference: reference.trim(), status: 'COMPLETED' },
      });
      if (existing?.shipForMeRequestId === row.id && row.status === 'PAID') {
        return tx.shipForMeRequest.findUnique({ where: { id: row.id }, select: shipForMeQuoteSelect });
      }
      if (existing || row.status === 'PAID') fail(409, 'This payment or request already has a verified record.');
      const now = new Date();
      const payment = await tx.payment.create({ data: {
        shipForMeRequestId: row.id, customerId: row.customerId, organizationId: row.organizationId,
        amountMinor, currency: 'USD', paymentMethod: 'MANUAL', providerReference: reference.trim(),
        purpose: 'QUOTE_PAYMENT', status: 'COMPLETED', verifiedBy: req.user.id, verifiedAt: now, completedAt: now,
      } });
      const saved = await tx.shipForMeRequest.update({
        where: { id: row.id }, data: { status: 'PAID', paymentStatus: 'PAID', paidAt: now }, select: shipForMeQuoteSelect,
      });
      await audit(tx, req, 'ShipForMeRequest', row.id, 'SHIP_FOR_ME_PAYMENT_VERIFIED', JSON.stringify({ paymentId: payment.id, amountMinor }));
      return saved;
    });
    res.json(result);
  } catch (error) { next(error); }
});

router.get('/retailers', async (req, res, next) => {
  try {
    const { retailerLinks } = await prisma.organization.findUniqueOrThrow({ where: { id: req.organizationId }, select: { retailerLinks: true } });
    res.json(retailerLinks ?? defaultRetailers);
  } catch (e) { next(e); }
});

router.put('/retailers', async (req, res, next) => {
  try {
    const { stores, previous } = req.body || {};
    if (!Array.isArray(stores) || stores.length > 100 || stores.some(store => !store || !['US', 'FR'].includes(store.country) ||
      !validText(store.name, 60) || !validRetailerUrl(store.url) || (store.logoUrl && !validRetailerUrl(store.logoUrl)) || typeof store.enabled !== 'boolean')) {
      fail(400, 'Enter a name, country and HTTPS retailer link for every store.');
    }
    const retailerLinks = stores.map(({ name, country, url, logoUrl, enabled }) => ({ name: name.trim(), country, url: url.trim(), logoUrl: logoUrl?.trim() || null, enabled }));
    await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const current = await tx.organization.findUniqueOrThrow({ where: { id: req.organizationId }, select: { retailerLinks: true } });
      if (JSON.stringify(current.retailerLinks ?? defaultRetailers) !== JSON.stringify(previous)) fail(409, 'Retailers changed. Reopen the editor to load the latest list.');
      await tx.organization.update({ where: { id: req.organizationId }, data: { retailerLinks } });
      await audit(tx, req, 'Organization', req.organizationId, 'RETAILERS_UPDATE', `${stores.length} retailer links`);
    });
    res.json(retailerLinks);
  } catch (e) { next(e); }
});

const validBps = (v) => Number.isSafeInteger(v) && v >= 0 && v <= 5000;

// ══════════════════════════════════════════════════════════════════════════════
// CUSTOMER AGREEMENTS (terms & conditions)
// ══════════════════════════════════════════════════════════════════════════════

const agreementSelect = {
  id: true, version: true, title: true, content: true, serviceType: true,
  isActive: true, effectiveFrom: true, createdAt: true, updatedAt: true,
  _count: { select: { acceptances: true } },
};

router.get('/agreements', async (req, res, next) => {
  try {
    const serviceType = typeof req.query.serviceType === 'string' ? req.query.serviceType : null;
    const agreements = await prisma.customerAgreement.findMany({
      where: { ...(serviceType ? { serviceType } : {}) },
      select: agreementSelect,
      orderBy: [{ serviceType: 'asc' }, { effectiveFrom: 'desc' }],
      take: 100,
    });
    res.json(agreements);
  } catch (e) { next(e); }
});

router.post('/agreements', async (req, res, next) => {
  try {
    const { version, title, content, serviceType, isActive = true, effectiveFrom } = req.body || {};
    if (!validText(version, 50)) fail(400, 'Enter a version (e.g. ship-for-me-v1.0).');
    if (!validText(title, 200)) fail(400, 'Enter a title.');
    if (!validText(content, 10000)) fail(400, 'Enter the terms content.');
    if (!['SHIP_FOR_ME', 'BUY_FOR_ME', 'GENERAL'].includes(serviceType)) {
      fail(400, 'Choose a valid service type.');
    }
    const ef = effectiveFrom ? new Date(effectiveFrom) : new Date();
    if (Number.isNaN(ef.getTime())) fail(400, 'Enter a valid effective date.');
    const result = await prisma.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended('customer-agreements', 0))`;
      if (isActive && ef <= new Date()) {
        await tx.customerAgreement.updateMany({
          where: { serviceType, isActive: true },
          data: { isActive: false },
        });
      }
      const created = await tx.customerAgreement.create({
        data: { version, title, content, serviceType, isActive, effectiveFrom: ef },
        select: agreementSelect,
      });
      await audit(tx, req, 'CustomerAgreement', created.id, 'AGREEMENT_CREATE', `v${version} ${serviceType}`);
      return created;
    });
    res.status(201).json(result);
  } catch (e) { if (e.code === 'P2002') return next(Object.assign(new Error('Choose a new terms version.'), { status: 409 })); next(e); }
});

router.patch('/agreements/:id', async (req, res, next) => {
  try {
    const { title, content, isActive, effectiveFrom } = req.body || {};
    const data = {};
    if (title !== undefined) { if (!validText(title, 200)) fail(400, 'Enter a title.'); data.title = title.trim(); }
    if (content !== undefined) { if (!validText(content, 10000)) fail(400, 'Enter the terms content.'); data.content = content.trim(); }
    if (isActive !== undefined) { if (typeof isActive !== 'boolean') fail(400, 'isActive must be boolean.'); data.isActive = isActive; }
    if (effectiveFrom !== undefined) { const ef = new Date(effectiveFrom); if (Number.isNaN(ef.getTime())) fail(400, 'Invalid date.'); data.effectiveFrom = ef; }
    if (Object.keys(data).length === 0) fail(400, 'No changes provided.');
    const result = await prisma.$transaction(async tx => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended('customer-agreements', 0))`;
      const existing = await tx.customerAgreement.findUnique({ where: { id: req.params.id }, select: agreementSelect });
      if (!existing) fail(404, 'Terms version not found.');
      if (existing._count.acceptances && (data.content || data.title || data.effectiveFrom)) fail(409, 'Publish a new version to change accepted terms.');
      if (data.isActive === true && (data.effectiveFrom ?? existing.effectiveFrom) <= new Date()) {
        await tx.customerAgreement.updateMany({
          where: { serviceType: existing.serviceType, isActive: true, id: { not: req.params.id } },
          data: { isActive: false },
        });
      }
      const updated = await tx.customerAgreement.update({ where: { id: req.params.id }, data, select: agreementSelect });
      await audit(tx, req, 'CustomerAgreement', req.params.id, 'AGREEMENT_UPDATE', updated.version);
      return updated;
    });
    res.json(result);
  } catch (e) { next(e); }
});

// ══════════════════════════════════════════════════════════════════════════════
// WAREHOUSE ADDRESSES
// ══════════════════════════════════════════════════════════════════════════════

const addressSelect = {
  id: true, label: true, addressLine1: true, addressLine2: true,
  city: true, stateProvince: true, postalCode: true, country: true,
  phone: true, email: true, isActive: true, isDefault: true,
  createdAt: true, updatedAt: true,
};

router.get('/warehouse-addresses', async (req, res, next) => {
  try {
    const addresses = await prisma.warehouseAddress.findMany({
      where: { organizationId: req.organizationId },
      select: addressSelect,
      orderBy: [{ isDefault: 'desc' }, { label: 'asc' }],
      take: 100,
    });
    res.json(addresses);
  } catch (e) { next(e); }
});

router.post('/warehouse-addresses', async (req, res, next) => {
  try {
    const { label, addressLine1, addressLine2, city, stateProvince, postalCode, country, phone, email, isActive = true, isDefault = false } = req.body || {};
    if (!validText(label, 100)) fail(400, 'Enter a label.');
    if (!validText(addressLine1, 200)) fail(400, 'Enter address line 1.');
    if (!validText(city, 100)) fail(400, 'Enter a city.');
    if (!validText(postalCode, 20)) fail(400, 'Enter a postal code.');
    if (!validText(country, 100)) fail(400, 'Enter a country.');
    if (isDefault) {
      await prisma.warehouseAddress.updateMany({
        where: { organizationId: req.organizationId, isDefault: true },
        data: { isDefault: false },
      });
    }
    const result = await prisma.warehouseAddress.create({
      data: {
        organizationId: req.organizationId,
        label: label.trim(),
        addressLine1: addressLine1.trim(),
        addressLine2: addressLine2?.trim() || null,
        city: city.trim(),
        stateProvince: stateProvince?.trim() || null,
        postalCode: postalCode.trim(),
        country: country.trim(),
        phone: phone?.trim() || null,
        email: email?.trim() || null,
        isActive,
        isDefault,
      },
      select: addressSelect,
    });
    await audit(prisma, req, 'WarehouseAddress', result.id, 'WAREHOUSE_ADDRESS_CREATE', result.label);
    res.status(201).json(result);
  } catch (e) { next(e); }
});

router.patch('/warehouse-addresses/:id', async (req, res, next) => {
  try {
    const { label, addressLine1, addressLine2, city, stateProvince, postalCode, country, phone, email, isActive, isDefault } = req.body || {};
    const data = {};
    if (label !== undefined) { if (!validText(label, 100)) fail(400, 'Enter a label.'); data.label = label.trim(); }
    if (addressLine1 !== undefined) { if (!validText(addressLine1, 200)) fail(400, 'Enter address line 1.'); data.addressLine1 = addressLine1.trim(); }
    if (addressLine2 !== undefined) data.addressLine2 = addressLine2?.trim() || null;
    if (city !== undefined) { if (!validText(city, 100)) fail(400, 'Enter a city.'); data.city = city.trim(); }
    if (stateProvince !== undefined) data.stateProvince = stateProvince?.trim() || null;
    if (postalCode !== undefined) { if (!validText(postalCode, 20)) fail(400, 'Enter a postal code.'); data.postalCode = postalCode.trim(); }
    if (country !== undefined) { if (!validText(country, 100)) fail(400, 'Enter a country.'); data.country = country.trim(); }
    if (phone !== undefined) data.phone = phone?.trim() || null;
    if (email !== undefined) data.email = email?.trim() || null;
    if (isActive !== undefined) data.isActive = isActive;
    if (isDefault === true) {
      await prisma.warehouseAddress.updateMany({
        where: { organizationId: req.organizationId, isDefault: true, id: { not: req.params.id } },
        data: { isDefault: false },
      });
      data.isDefault = true;
    }
    if (Object.keys(data).length === 0) fail(400, 'No changes provided.');
    const result = await prisma.warehouseAddress.update({
      where: { id: req.params.id, organizationId: req.organizationId },
      data,
      select: addressSelect,
    });
    await audit(prisma, req, 'WarehouseAddress', req.params.id, 'WAREHOUSE_ADDRESS_UPDATE', JSON.stringify(data));
    res.json(result);
  } catch (e) { next(e); }
});

// ══════════════════════════════════════════════════════════════════════════════
// PAYMENT METHOD CONFIG (by country & service)
// ══════════════════════════════════════════════════════════════════════════════

const methodConfigSelect = {
  id: true, serviceType: true, countryCode: true, method: true, provider: true,
  isActive: true, minAmountMinor: true, maxAmountMinor: true, feePercent: true,
  feeFixedMinor: true, config: true, createdAt: true, updatedAt: true,
};

router.get('/payment-methods', async (req, res, next) => {
  try {
    const serviceType = typeof req.query.serviceType === 'string' ? req.query.serviceType : null;
    const countryCode = typeof req.query.countryCode === 'string' ? req.query.countryCode : null;
    const methods = await prisma.paymentMethodConfig.findMany({
      where: {
        organizationId: req.organizationId,
        ...(serviceType ? { serviceType } : {}),
        ...(countryCode ? { countryCode } : {}),
        isActive: true,
      },
      select: methodConfigSelect,
      orderBy: [{ serviceType: 'asc' }, { countryCode: 'asc' }, { method: 'asc' }],
      take: 100,
    });
    res.json(methods);
  } catch (e) { next(e); }
});

router.post('/payment-methods', async (req, res, next) => {
  try {
    const { serviceType, countryCode, method, provider, minAmountMinor, maxAmountMinor, feePercent = 0, feeFixedMinor = 0, config } = req.body || {};
    if (!['BUY_FOR_ME', 'SHIP_FOR_ME', 'MARKETPLACE', 'ALL'].includes(serviceType)) {
      fail(400, 'Choose a valid service type.');
    }
    if (!['CARD', 'BANK_TRANSFER', 'MOBILE_MONEY', 'MANUAL'].includes(method)) {
      fail(400, 'Choose a valid payment method.');
    }
    if (countryCode && !validText(countryCode, 10)) fail(400, 'Enter a valid country code.');
    if (minAmountMinor != null && !validAmount(minAmountMinor)) fail(400, 'Invalid min amount.');
    if (maxAmountMinor != null && !validAmount(maxAmountMinor)) fail(400, 'Invalid max amount.');
    if (!validBps(feePercent)) fail(400, 'Fee percent must be 0-50%.');
    if (feeFixedMinor != null && !validAmount(feeFixedMinor)) fail(400, 'Invalid fixed fee.');
    const result = await prisma.paymentMethodConfig.create({
      data: {
        organizationId: req.organizationId,
        serviceType,
        countryCode: countryCode || 'ALL',
        method,
        provider: provider || null,
        minAmountMinor: minAmountMinor || null,
        maxAmountMinor: maxAmountMinor || null,
        feePercent,
        feeFixedMinor: feeFixedMinor || 0,
        config: config || null,
      },
      select: methodConfigSelect,
    });
    await audit(prisma, req, 'PaymentMethodConfig', result.id, 'PAYMENT_METHOD_CREATE', `${method} ${countryCode || 'ALL'}`);
    res.status(201).json(result);
  } catch (e) { next(e); }
});

router.patch('/payment-methods/:id', async (req, res, next) => {
  try {
    const { isActive, provider, minAmountMinor, maxAmountMinor, feePercent, feeFixedMinor, config } = req.body || {};
    const data = {};
    if (isActive !== undefined) data.isActive = isActive;
    if (provider !== undefined) data.provider = provider?.trim() || null;
    if (minAmountMinor != null) { if (!validAmount(minAmountMinor)) fail(400, 'Invalid min amount.'); data.minAmountMinor = minAmountMinor; }
    if (maxAmountMinor != null) { if (!validAmount(maxAmountMinor)) fail(400, 'Invalid max amount.'); data.maxAmountMinor = maxAmountMinor; }
    if (feePercent != null) { if (!validBps(feePercent)) fail(400, 'Fee percent must be 0-50%.'); data.feePercent = feePercent; }
    if (feeFixedMinor != null) { if (!validAmount(feeFixedMinor)) fail(400, 'Invalid fixed fee.'); data.feeFixedMinor = feeFixedMinor; }
    if (config !== undefined) data.config = config;
    if (Object.keys(data).length === 0) fail(400, 'No changes provided.');
    const result = await prisma.paymentMethodConfig.update({
      where: { id: req.params.id, organizationId: req.organizationId },
      data,
      select: methodConfigSelect,
    });
    await audit(prisma, req, 'PaymentMethodConfig', req.params.id, 'PAYMENT_METHOD_UPDATE', JSON.stringify(data));
    res.json(result);
  } catch (e) { next(e); }
});

// ══════════════════════════════════════════════════════════════════════════════
// RETURN REQUESTS (admin review)
// ══════════════════════════════════════════════════════════════════════════════

const returnSelect = {
  id: true, reason: true, description: true, requestedAmountMinor: true,
  status: true, adminDecision: true, decidedAt: true, decidedBy: true,
  createdAt: true, updatedAt: true,
  buyForMeRequest: { select: { id: true, title: true, status: true } },
  shipForMeRequest: { select: { id: true, itemDescription: true, status: true } },
  customer: { select: { id: true, displayName: true, email: true } },
};

router.get('/returns', async (req, res, next) => {
  try {
    const status = typeof req.query.status === 'string' ? req.query.status.toUpperCase() : null;
    const returns = await prisma.returnRequest.findMany({
      where: { organizationId: req.organizationId, ...(status ? { status } : {}) },
      select: returnSelect,
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    res.json(returns);
  } catch (e) { next(e); }
});

router.patch('/returns/:id', async (req, res, next) => {
  try {
    const { status, adminDecision } = req.body || {};
    if (!['PENDING', 'APPROVED', 'REJECTED', 'COMPLETED'].includes(status)) {
      fail(400, 'Choose a valid status.');
    }
    const result = await prisma.$transaction(async (tx) => {
      const existing = await tx.returnRequest.findFirst({
        where: { id: req.params.id, organizationId: req.organizationId },
      });
      if (!existing) fail(404, 'Return request not found.');
      const updated = await tx.returnRequest.update({
        where: { id: existing.id },
        data: {
          status,
          adminDecision: adminDecision?.trim() || null,
          ...(status !== 'PENDING' && { decidedAt: new Date(), decidedBy: req.user.id }),
        },
        select: returnSelect,
      });
      await audit(tx, req, 'ReturnRequest', existing.id, 'RETURN_REVIEW', `${existing.status} → ${status}`);
      return updated;
    });
    res.json(result);
  } catch (e) { next(e); }
});

export default router;
