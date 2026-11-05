// Admin routes for Buy For Me / Ship For Me service configuration.
// Mounted at /admin/commerce/services
import { Router } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { fail, warehouseLock } from '../warehouse.js';
import { audit, validAmount, validOptionalText, validText, currencies } from '../shopfront.js';
import { createNotification } from '../notifications.js';
import { resolveOrganizationId } from '../tracking.js';

const router = Router();
router.use(authenticate, requireRole('ADMIN'), async (req, res, next) => {
  try { req.organizationId = await resolveOrganizationId(prisma, req.user); next(); } catch (e) { next(e); }
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
      // If activating this version, deactivate others of same service type
      if (isActive) {
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
  } catch (e) { next(e); }
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
    if (data.isActive === true) {
      const existing = await prisma.customerAgreement.findUnique({ where: { id: req.params.id } });
      if (existing) {
        await prisma.customerAgreement.updateMany({
          where: { serviceType: existing.serviceType, isActive: true, id: { not: req.params.id } },
          data: { isActive: false },
        });
      }
    }
    const result = await prisma.customerAgreement.update({
      where: { id: req.params.id },
      data,
      select: agreementSelect,
    });
    await audit(prisma, req, 'CustomerAgreement', req.params.id, 'AGREEMENT_UPDATE', JSON.stringify(data));
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
