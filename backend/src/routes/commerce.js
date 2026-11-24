import { deliveryRequirement, marketplaceDeliveryMethod, marketplaceDeliveryMethods, marketplaceInvoice, marketplaceNotice, marketplaceTransitions, openOrderIssue, payableBalance, refundTotal, requirePaid } from '../marketplace_orders.js';
import { Router, raw } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { resolveOrganizationId } from '../tracking.js';
import { fail, warehouseLock } from '../warehouse.js';
import { calculateFees, reserveStock, releaseStock, validOptionalText } from '../shopfront.js';
const router = Router();
router.use(authenticate, requireRole('ADMIN'), async (req, res, next) => {
  try { req.organizationId = await resolveOrganizationId(prisma, req.user); next(); } catch (e) { next(e); }
});
const validText = (v, max = 200) => typeof v === 'string' && v.trim().length > 0 && v.length <= max;
const validAmount = v => Number.isSafeInteger(v) && v >= 0 && v <= 1000000000;
const currencies = ['USD', 'EUR', 'XOF'];
const orderInclude = {
  customer: { select: { id: true, displayName: true } },
  product: { select: { title: true } },
  marketplaceIssues: { orderBy: { createdAt: 'desc' }, take: 30 },
  parcel: { select: { trackingId: true, id: true } },
  seller: { select: { id: true, displayName: true } },
  paymentSubmissions: {
    select: { id: true, method: true, transactionId: true, status: true, reviewNote: true, createdAt: true },
    orderBy: { createdAt: 'desc' },
    take: 25,
  },
  updates: {
    select: {
      id: true, status: true, message: true, deliveryService: true, shippingCarrier: true,
      shippingTrackingNumber: true, shippingLabelUrl: true, fileName: true, contentType: true, createdAt: true,
    },
    orderBy: { createdAt: 'desc' },
    take: 50,
  },
};
const transitions = {
  MARKETPLACE: marketplaceTransitions,
  BUY_FOR_ME: { REQUESTED: ['QUOTED', 'CANCELLED'], QUOTED: ['ACCEPTED', 'CANCELLED'], ACCEPTED: ['PAYMENT_CONFIRMED', 'PURCHASED', 'CANCELLED'], PAYMENT_CONFIRMED: ['PURCHASED'], PURCHASED: ['RECEIVED'], RECEIVED: ['SHIPPED'], SHIPPED: ['COMPLETED'], COMPLETED: [], CANCELLED: [] },
};
async function audit(tx, req, entity, id, action, detail) {
  await tx.auditLog.create({ data: { actorId: req.user.id, action, entity, entityId: id, detail } });
}
// ── Marketplace sellers ──────────────────────────────────────────────────────
// Self-serve applicants and D2F-onboarded sellers share one review flow. The
// commission rate is agreed in this step — before any sale can take place.

const sellerStatuses = ['PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED'];
const validBps = (v) => Number.isSafeInteger(v) && v >= 0 && v <= 5000;

const sellerInclude = {
  user: { select: { id: true, fullName: true, email: true, phone: true, createdAt: true } },
  _count: { select: { products: true, orders: true } },
};

router.get('/sellers', async (req, res, next) => {
  try {
    const status = typeof req.query.status === 'string' ? req.query.status.toUpperCase() : null;
    if (status && !sellerStatuses.includes(status)) fail(400, 'Choose a valid seller status.');
    const sellers = await prisma.sellerProfile.findMany({
      where: { organizationId: req.organizationId, ...(status ? { status } : {}) },
      include: sellerInclude,
      orderBy: [{ status: 'asc' }, { storefrontOrder: 'asc' }, { createdAt: 'desc' }],
      take: 200,
    });
    res.json(sellers);
  } catch (e) { next(e); }
});

// Admin onboarding: register an app account as an approved seller without the
// in-app application. The person must already have a D2F account (a customer
// profile linked to the app); D2F agrees the commission rate here.
router.post('/sellers', async (req, res, next) => {
  try {
    const { customerId, displayName, businessType = 'INDIVIDUAL', businessName, category, country, city, phone, commissionBps = 1000, headline, bio } = req.body || {};
    if (typeof customerId !== 'string') fail(400, 'Choose the customer account to register as a seller.');
    if (!validBps(commissionBps)) fail(400, 'Commission must be between 0% and 50%.');
    if (businessType !== 'INDIVIDUAL' && businessType !== 'BUSINESS') fail(400, 'Choose individual or business.');
    const result = await prisma.$transaction(async (tx) => {
      await warehouseLock(tx, req.organizationId);
      const customer = await tx.customer.findFirst({ where: { id: customerId, organizationId: req.organizationId }, include: { user: { select: { id: true, fullName: true, email: true, phone: true } } } });
      if (!customer) fail(404, 'Customer not found.');
      if (!customer.userId || !customer.user) fail(400, 'This customer profile has no app account yet. Ask them to register in the app, then register them as a seller.');
      if (!validText(displayName ?? customer.displayName, 120)) fail(400, 'Enter a seller name.');
      if (!validText(category, 80)) fail(400, 'Enter the seller’s main category.');
      const effectiveCountry = typeof country === 'string' && country.trim() ? country.trim() : customer.country;
      if (!validText(effectiveCountry, 80)) fail(400, 'Enter the seller’s country.');
      const effectivePhone = typeof phone === 'string' && phone.trim() ? phone.trim() : customer.phone || customer.user.phone;
      if (!validText(effectivePhone, 40)) fail(400, 'Enter a contact phone.');
      if (businessType === 'BUSINESS' && !validText(businessName, 160)) fail(400, 'Enter the business name.');
      const created = await tx.sellerProfile.create({
        data: {
          organizationId: req.organizationId,
          userId: customer.userId,
          status: 'APPROVED',
          displayName: (displayName?.trim() || customer.displayName).trim(),
          businessType,
          businessName: businessType === 'BUSINESS' ? businessName.trim() : null,
          headline: headline?.trim() || null,
          bio: bio?.trim() || null,
          category: category.trim(),
          phone: effectivePhone.trim(),
          email: customer.user.email,
          country: effectiveCountry,
          city: (typeof city === 'string' && city.trim()) || customer.city,
          commissionBps,
          reviewedAt: new Date(),
          reviewedById: req.user.id,
          reviewNote: 'Registered by D2F administrator',
        },
        include: sellerInclude,
      });
      await audit(tx, req, 'SellerProfile', created.id, 'SELLER_ADMIN_REGISTER', created.displayName);
      return created;
    });
    res.status(201).json(result);
  } catch (e) {
    if (e?.code === 'P2002') return next(Object.assign(new Error('This account already has a seller profile.'), { status: 409 }));
    next(e);
  }
});

const sellerActions = {
  approve: { from: ['PENDING', 'REJECTED'], to: 'APPROVED', requireNote: false, label: 'SELLER_APPROVE' },
  reject: { from: ['PENDING'], to: 'REJECTED', requireNote: true, label: 'SELLER_REJECT' },
  suspend: { from: ['APPROVED'], to: 'SUSPENDED', requireNote: true, label: 'SELLER_SUSPEND' },
  reinstate: { from: ['SUSPENDED'], to: 'APPROVED', requireNote: false, label: 'SELLER_REINSTATE' },
};

router.patch('/sellers/:id', async (req, res, next) => {
  try {
    const { action, commissionBps, reviewNote } = req.body || {};
    const rule = sellerActions[action];
    if (!rule) fail(400, 'Choose approve, reject, suspend or reinstate.');
    const note = typeof reviewNote === 'string' ? reviewNote.trim() : '';
    if (rule.requireNote && !validText(note, 500)) fail(400, 'Add a short note the seller will see.');
    if (commissionBps !== undefined && !validBps(commissionBps)) fail(400, 'Commission must be between 0% and 50%.');
    const result = await prisma.$transaction(async (tx) => {
      await warehouseLock(tx, req.organizationId);
      const existing = await tx.sellerProfile.findFirst({ where: { id: req.params.id, organizationId: req.organizationId } });
      if (!existing) fail(404, 'Seller not found.');
      if (!rule.from.includes(existing.status)) fail(409, `This seller is ${existing.status.toLowerCase()} — refresh and try again.`);
      const data = {
        status: rule.to,
        reviewNote: note || null,
        reviewedAt: new Date(),
        reviewedById: req.user.id,
      };
      // The commission rate is agreed at approval — before the first sale.
      if (action === 'approve' && commissionBps !== undefined) data.commissionBps = commissionBps;
      const updated = await tx.sellerProfile.update({ where: { id: existing.id }, data, include: sellerInclude });
      await audit(tx, req, 'SellerProfile', existing.id, rule.label, note || `${existing.status} → ${rule.to}${data.commissionBps != null ? ` · commission ${data.commissionBps}bps` : ''}`);
      return updated;
    });
    res.json(result);
  } catch (e) { next(e); }
});

router.patch('/sellers/:id/storefront', async (req, res, next) => {
  try {
    const { displayName, city, country, category, headline, bio, whatsappNumber, storefrontOrder, localDeliveryEnabled } = req.body || {};
    if (!validText(displayName, 120) || !validText(country, 80) || !validText(category, 80) ||
      !validOptionalText(city, 120) || !validOptionalText(headline, 160) || !validOptionalText(bio, 2000) ||
      (whatsappNumber && !/^\+[1-9]\d{7,14}$/.test(whatsappNumber)) ||
      !Number.isSafeInteger(storefrontOrder) || storefrontOrder < 0 || storefrontOrder > 10000 ||
      typeof localDeliveryEnabled !== 'boolean') fail(400, 'Enter valid seller details and an international WhatsApp number if supplied.');
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const seller = await tx.sellerProfile.findFirst({ where: { id: req.params.id, organizationId: req.organizationId } });
      if (!seller) fail(404, 'Seller not found.');
      const updated = await tx.sellerProfile.update({ where: { id: seller.id }, data: {
        displayName: displayName.trim(), city: city?.trim() || null, country: country.trim(), category: category.trim(),
        headline: headline?.trim() || null, bio: bio?.trim() || null, whatsappNumber: whatsappNumber || null, storefrontOrder, localDeliveryEnabled,
      } });
      await audit(tx, req, 'SellerProfile', seller.id, 'SELLER_STOREFRONT_UPDATED', updated.displayName);
      const { profilePicture, banner, ...profile } = updated;
      return profile;
    });
    res.json(result);
  } catch (e) { next(e); }
});

// Commission report: merchandise volume and D2F earnings per seller for a
// period. D2F catalog sales carry no commission; cancelled orders are excluded.
router.get('/commissions', async (req, res, next) => {
  try {
    const now = new Date();
    const from = req.query.from ? new Date(req.query.from) : new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    const to = req.query.to ? new Date(req.query.to) : now;
    if (Number.isNaN(from.getTime()) || Number.isNaN(to.getTime()) || from > to) fail(400, 'Choose a valid date range.');
    const baseWhere = { organizationId: req.organizationId, kind: 'MARKETPLACE', createdAt: { gte: from, lte: to }, status: { not: 'CANCELLED' } };
    // Money never sums across currencies; report each currency separately.
    const [byCurrency, bySeller] = await prisma.$transaction([
      prisma.serviceOrder.groupBy({
        by: ['currency'],
        where: { ...baseWhere, commissionBps: { not: null } },
        _count: { _all: true },
        _sum: { amountMinor: true, commissionMinor: true },
        orderBy: { currency: 'asc' },
      }),
      prisma.serviceOrder.groupBy({
        by: ['sellerId', 'currency'],
        where: { ...baseWhere, sellerId: { not: null } },
        _count: { _all: true },
        _sum: { amountMinor: true, commissionMinor: true },
        orderBy: [{ sellerId: 'asc' }, { currency: 'asc' }],
      }),
    ]);
    const sellers = bySeller.length
      ? await prisma.sellerProfile.findMany({ where: { id: { in: [...new Set(bySeller.map((row) => row.sellerId))] } }, select: { id: true, displayName: true } })
      : [];
    const nameById = new Map(sellers.map((seller) => [seller.id, seller.displayName]));
    res.json({
      from,
      to,
      currencies: byCurrency.map((row) => ({
        currency: row.currency,
        orders: row._count._all,
        merchandiseMinor: row._sum.amountMinor ?? 0,
        commissionMinor: row._sum.commissionMinor ?? 0,
      })),
      sellers: bySeller.map((row) => ({
        sellerId: row.sellerId,
        displayName: nameById.get(row.sellerId) ?? 'Former seller',
        currency: row.currency,
        orders: row._count._all,
        merchandiseMinor: row._sum.amountMinor ?? 0,
        commissionMinor: row._sum.commissionMinor ?? 0,
      })),
    });
  } catch (e) { next(e); }
});

router.get('/:kind', async (req, res, next) => {
  try {
    const kind = req.params.kind.toUpperCase();
    if (!transitions[kind]) fail(400, 'Choose Marketplace or Buy For Me.');
    const limit = Number(req.query.limit ?? 50), offset = Number(req.query.offset ?? 0);
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100 || !Number.isSafeInteger(offset) || offset < 0) fail(400, 'Invalid page.');
    const where = { organizationId: req.organizationId, kind };
    const [orders, total, products] = await prisma.$transaction([
      prisma.serviceOrder.findMany({ where, include: orderInclude, orderBy: [{ createdAt: 'desc' }, { id: 'asc' }], take: limit, skip: offset }),
      prisma.serviceOrder.count({ where }),
      prisma.product.findMany({ where: { organizationId: req.organizationId }, orderBy: { title: 'asc' }, include: { seller: { select: { id: true, displayName: true } } } }),
    ]);
    res.json({
      orders: kind === 'BUY_FOR_ME'
        ? orders.map(order => ({ ...order, paymentInstructions: process.env.D2F_ZELLE_ACCOUNT ? `Zelle: ${process.env.D2F_ZELLE_ACCOUNT}` : 'Payment instructions are not configured. Contact D2F before requesting payment.' }))
        : orders,
      total, products, limit, offset, transitions: transitions[kind],
    });
  } catch (e) { next(e); }
});

router.get('/orders/:id/payment-submissions/:submissionId/image', async (req, res, next) => {
  try {
    const order = await prisma.serviceOrder.findFirst({
      where: { id: req.params.id, organizationId: req.organizationId, kind: 'BUY_FOR_ME' },
      select: { id: true },
    });
    if (!order) fail(404, 'Payment evidence not found.');
    const submission = await prisma.serviceOrderPaymentSubmission.findFirst({
      where: { id: req.params.submissionId, serviceOrderId: order.id },
    });
    if (!submission?.bytes) fail(404, 'Payment evidence not found.');
    res.set({
      'Content-Type': submission.contentType,
      'Cache-Control': 'private, no-store',
      'X-Content-Type-Options': 'nosniff',
      'Content-Disposition': 'inline; filename="payment-proof"',
    }).send(submission.bytes);
  } catch (e) { next(e); }
});

router.post('/orders/:id/payment-submissions/:submissionId/review', async (req, res, next) => {
  try {
    const { accepted, note } = req.body || {};
    if (typeof accepted !== 'boolean') fail(400, 'Choose whether the payment evidence is verified.');
    if (!accepted && !validText(note, 1000)) fail(400, 'Explain what needs to be corrected.');
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const order = await tx.serviceOrder.findFirst({
        where: { id: req.params.id, organizationId: req.organizationId, kind: 'BUY_FOR_ME' },
      });
      if (!order) fail(404, 'Purchase request not found.');
      const submission = await tx.serviceOrderPaymentSubmission.findFirst({
        where: { id: req.params.submissionId, serviceOrderId: order.id, status: 'PENDING' },
      });
      if (!submission || order.status !== 'ACCEPTED') fail(409, 'This payment evidence is no longer awaiting review.');
      const updatedSubmission = await tx.serviceOrderPaymentSubmission.update({
        where: { id: submission.id },
        data: {
          status: accepted ? 'VERIFIED' : 'REJECTED',
          reviewNote: accepted ? null : note.trim(),
          reviewedById: req.user.id,
          reviewedAt: new Date(),
        },
      });
      const updatedOrder = await tx.serviceOrder.update({
        where: { id: order.id },
        data: {
          paymentStatus: accepted ? 'VERIFIED' : 'REJECTED',
          ...(accepted ? { status: 'PAYMENT_CONFIRMED' } : {}),
        },
        include: orderInclude,
      });
      await tx.serviceOrderUpdate.create({
        data: {
          serviceOrderId: order.id,
          actorId: req.user.id,
          status: accepted ? 'PAYMENT_CONFIRMED' : null,
          message: accepted ? 'Payment received and verified by D2F.' : `Payment proof needs correction: ${note.trim()}`,
        },
      });
      await audit(tx, req, 'ServiceOrder', order.id, accepted ? 'BUY_FOR_ME_PAYMENT_VERIFIED' : 'BUY_FOR_ME_PAYMENT_REJECTED', submission.transactionId);
      return { order: updatedOrder, submission: updatedSubmission };
    });
    res.json(result);
  } catch (e) { next(e); }
});

router.post('/orders/:id/updates', raw({ type: ['image/jpeg', 'image/png', 'image/webp'], limit: '4mb' }), async (req, res, next) => {
  try {
    const body = Buffer.isBuffer(req.body) ? req.query : (req.body || {});
    const bytes = Buffer.isBuffer(req.body) ? req.body : null;
    const mime = bytes ? req.headers['content-type']?.split(';')[0] : null;
    if (bytes && !(bytes.length > 12 && (
      (mime === 'image/jpeg' && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) ||
      (mime === 'image/png' && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) ||
      (mime === 'image/webp' && bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP')
    ))) fail(400, 'Upload a valid JPEG, PNG or WebP image (up to 4 MB).');
    const message = body.message;
    const status = body.status || null;
    const deliveryService = body.deliveryService || null;
    const shippingCarrier = body.shippingCarrier || null;
    const shippingTrackingNumber = body.shippingTrackingNumber || null;
    const shippingLabelUrl = body.shippingLabelUrl || null;
    if (!validText(message, 1000) && !bytes) fail(400, 'Add a customer update or an image.');
    if (status !== null && (!transitions.BUY_FOR_ME[status] || status === 'PAYMENT_CONFIRMED')) fail(400, 'Choose a valid customer-visible status.');
    if (status === 'QUOTED') fail(409, 'Send a quote using the product and shipping cost fields.');
    if (deliveryService && !['D2F_CONNECT', 'AIR_CARGO', 'SEA', 'AIR_TRAVELLER'].includes(deliveryService)) fail(400, 'Choose an available D2F delivery service.');
    if (!validOptionalText(shippingCarrier, 120) || !validOptionalText(shippingTrackingNumber, 120)) fail(400, 'Enter valid carrier and tracking details.');
    if (shippingLabelUrl) {
      try {
        if (!['http:', 'https:'].includes(new URL(shippingLabelUrl).protocol) || shippingLabelUrl.length > 2000) throw new Error();
      } catch {
        fail(400, 'Enter a secure HTTP or HTTPS shipping label link.');
      }
    }
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const order = await tx.serviceOrder.findFirst({
        where: { id: req.params.id, organizationId: req.organizationId, kind: 'BUY_FOR_ME' },
      });
      if (!order) fail(404, 'Purchase request not found.');
      if (status && !transitions.BUY_FOR_ME[order.status]?.includes(status)) fail(409, 'Invalid status change. Refresh this request.');
      if (status === 'PURCHASED' && order.paymentStatus !== 'VERIFIED') fail(409, 'Verify the customer payment before marking this item purchased.');
      const data = {
        ...(status ? { status } : {}),
        ...(deliveryService ? { deliveryService } : {}),
        ...(shippingCarrier ? { shippingCarrier } : {}),
        ...(shippingTrackingNumber ? { shippingTrackingNumber } : {}),
        ...(shippingLabelUrl ? { shippingLabelUrl } : {}),
      };
      if (status === 'SHIPPED' && !(shippingTrackingNumber || order.shippingTrackingNumber || order.trackingRef || order.parcelId)) {
        fail(400, 'Add a shipment tracking number before marking this request shipped.');
      }
      if (status === 'SHIPPED' && !(deliveryService || order.deliveryService)) {
        fail(400, 'Choose a D2F delivery option before marking this request shipped.');
      }
      if (Object.keys(data).length) await tx.serviceOrder.update({ where: { id: order.id }, data });
      const update = await tx.serviceOrderUpdate.create({
        data: {
          serviceOrderId: order.id,
          actorId: req.user.id,
          status,
          message: message?.trim() || (status ? `Your request is now ${status.toLowerCase().replaceAll('_', ' ')}.` : 'D2F added an update image.'),
          deliveryService,
          shippingCarrier,
          shippingTrackingNumber,
          shippingLabelUrl,
          fileName: bytes ? 'd2f-update' : null,
          contentType: mime,
          bytes,
        },
      });
      await audit(tx, req, 'ServiceOrderUpdate', update.id, 'BUY_FOR_ME_CUSTOMER_UPDATE', JSON.stringify({ orderId: order.id, status }));
      return { update, order: await tx.serviceOrder.findUnique({ where: { id: order.id }, include: orderInclude }) };
    });
    res.status(201).json(result.order);
  } catch (e) { next(e); }
});

router.get('/orders/:id/updates/:updateId/image', async (req, res, next) => {
  try {
    const order = await prisma.serviceOrder.findFirst({
      where: { id: req.params.id, organizationId: req.organizationId, kind: 'BUY_FOR_ME' },
      select: { id: true },
    });
    if (!order) fail(404, 'Update image not found.');
    const update = await prisma.serviceOrderUpdate.findFirst({
      where: { id: req.params.updateId, serviceOrderId: order.id },
    });
    if (!update?.bytes) fail(404, 'Update image not found.');
    res.set({
      'Content-Type': update.contentType,
      'Cache-Control': 'private, no-store',
      'X-Content-Type-Options': 'nosniff',
      'Content-Disposition': 'inline; filename="d2f-update"',
    }).send(update.bytes);
  } catch (e) { next(e); }
});
router.post('/products', async (req, res, next) => {
  try {
    const { title, category, description, priceMinor, currency = 'USD', isActive = false } = req.body || {};
    if (!validText(title) || !validText(category, 80) || !validAmount(priceMinor) || !currencies.includes(currency) || typeof isActive !== 'boolean' || (description != null && !validText(description, 2000))) fail(400, 'Enter a product title, category, valid price and currency.');
    const product = await prisma.$transaction(async tx => {
      const created = await tx.product.create({ data: { organizationId: req.organizationId, title: title.trim(), category: category.trim(), description: description?.trim() || null, priceMinor, currency, isActive } });
      await audit(tx, req, 'Product', created.id, 'PRODUCT_CREATE', created.title);
      return created;
    });
    res.status(201).json(product);
  } catch (e) { next(e); }
});
router.patch('/products/:id', async (req, res, next) => {
  try {
    const { isActive, title, category, description, priceMinor, currency, featured } = req.body || {};
    const data = {};
    if (isActive !== undefined) { if (typeof isActive !== 'boolean') fail(400, 'Availability must be true or false.'); data.isActive = isActive; }
    if (featured !== undefined) { if (typeof featured !== 'boolean') fail(400, 'Featured must be true or false.'); data.featured = featured; }
    for (const [key, value, max] of [['title', title, 200], ['category', category, 80]]) if (value !== undefined) { if (!validText(value, max)) fail(400, `Enter a valid ${key}.`); data[key] = value.trim(); }
    if (description !== undefined) { if (typeof description !== 'string' || description.length > 2000) fail(400, 'Enter a valid description.'); data.description = description.trim() || null; }
    if (priceMinor !== undefined) { if (!validAmount(priceMinor)) fail(400, 'Enter a valid price.'); data.priceMinor = priceMinor; }
    if (currency !== undefined) { if (!currencies.includes(currency)) fail(400, 'Choose a supported currency.'); data.currency = currency; }
    if (!Object.keys(data).length) fail(400, 'No changes provided.');
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const existing = await tx.product.findFirst({ where: { id: req.params.id, organizationId: req.organizationId } });
      if (!existing) fail(404, 'Product not found.');
      const updated = await tx.product.update({ where: { id: existing.id }, data });
      await audit(tx, req, 'Product', existing.id, 'PRODUCT_UPDATE', JSON.stringify(data));
      return updated;
    });
    res.json(result);
  } catch (e) { next(e); }
});
router.post('/orders', async (req, res, next) => {
  try {
    const { kind, customerId, productId, title, sourceUrl, quantity = 1, currency = 'USD', notes, deliveryMethod = 'D2F_DELIVERY' } = req.body || {};
    if (!transitions[kind] || typeof customerId !== 'string' || !Number.isSafeInteger(quantity) || quantity < 1 || quantity > 1000 || !currencies.includes(currency) || (notes != null && !validText(notes, 2000))) fail(400, 'Choose a customer, module, currency and valid quantity.');
    if (kind === 'BUY_FOR_ME' && !validText(title)) fail(400, 'Describe the requested item.');
    if (sourceUrl != null && typeof sourceUrl !== 'string') fail(400, 'Enter a valid product link.');
    if (sourceUrl) { try { if (!['http:', 'https:'].includes(new URL(sourceUrl).protocol) || sourceUrl.length > 2000) throw new Error(); } catch { fail(400, 'Enter a valid HTTP or HTTPS product link.'); } }
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      if (!await tx.customer.findFirst({ where: { id: customerId, organizationId: req.organizationId } })) fail(404, 'Customer not found.');
      let product, fees;
      if (kind === 'MARKETPLACE') {
        if (typeof productId !== 'string') fail(400, 'Choose an available product.');
        if (!marketplaceDeliveryMethods.includes(deliveryMethod)) fail(400, 'Choose a delivery method.');
        product = await tx.product.findFirst({ where: { id: productId, organizationId: req.organizationId, isActive: true, OR: [{ sellerId: null }, { seller: { status: 'APPROVED' } }] }, include: { seller: { select: { id: true, commissionBps: true } } } });
        if (!product) fail(400, 'Choose an available product.');
        if (!validAmount(product.priceMinor * quantity)) fail(400, 'Order total is too large.');
        if (!await reserveStock(tx, product.id, quantity)) fail(409, 'There is insufficient stock for this order.');
        fees = calculateFees(product.priceMinor * quantity, { seller: product.seller, deliveryPreference: deliveryMethod === 'D2F_DELIVERY' ? 'D2F' : 'SELLER', fulfillment: product.fulfillment, settings: await tx.commissionSettings.findFirst() });
        delete fees.totalFees;
      }
      const created = await tx.serviceOrder.create({ data: { organizationId: req.organizationId, kind, customerId,
        productId: product?.id, sellerId: product?.sellerId ?? null, title: product?.title || title.trim(), sourceUrl: sourceUrl || null,
        quantity, currency: product?.currency || currency, amountMinor: product ? product.priceMinor * quantity : null, notes: notes?.trim() || null,
        source: 'ADMIN',
        ...(product ? { ...fees, deliveryMethod } : {}) }, include: orderInclude });
      await audit(tx, req, 'ServiceOrder', created.id, 'SERVICE_ORDER_CREATE', `${kind}: ${created.title}`);
      return created;
    });
    res.status(201).json(result);
  } catch (e) { next(e); }
});
router.patch('/orders/:id', async (req, res, next) => {
  try {
    const {
      status, amountMinor, productCostMinor, shippingCostMinor, pickupFeeMinor, handlingFeeMinor, trackingId, notes, trackingRef,
      deliveryService, shippingCarrier, shippingTrackingNumber, shippingLabelUrl, customerMessage,
      deliveryMethod, shipmentEvidence, deliveryEvidence, statusReason,
    } = req.body || {};
    if (amountMinor !== undefined && !validAmount(amountMinor)) fail(400, 'Enter a valid quote total.');
    if (productCostMinor !== undefined && !validAmount(productCostMinor)) fail(400, 'Enter a valid product cost.');
    for (const fee of [pickupFeeMinor, handlingFeeMinor]) if (fee !== undefined && !validAmount(fee)) fail(400, 'Enter a valid pickup or handling fee.');
    if (shippingCostMinor !== undefined && !validAmount(shippingCostMinor)) fail(400, 'Enter a valid shipping cost.');
    if (notes !== undefined && (typeof notes !== 'string' || notes.length > 2000)) fail(400, 'Enter a valid note.');
    if (trackingRef !== undefined && (typeof trackingRef !== 'string' || trackingRef.length > 120)) fail(400, 'Carrier reference is too long.');
    if (trackingId !== undefined && !validText(trackingId, 80)) fail(400, 'Enter a tracking number.');
    if (customerMessage !== undefined && !validText(customerMessage, 1000)) fail(400, 'Enter a customer update.');
    if (deliveryService !== undefined && !['D2F_CONNECT', 'AIR_CARGO', 'SEA', 'AIR_TRAVELLER'].includes(deliveryService)) fail(400, 'Choose an available D2F delivery service.');
    if (shippingCarrier !== undefined && !validOptionalText(shippingCarrier, 120)) fail(400, 'Enter a valid shipping carrier.');
    if (shippingTrackingNumber !== undefined && !validOptionalText(shippingTrackingNumber, 120)) fail(400, 'Enter a valid shipping tracking number.');
    if (shippingLabelUrl !== undefined) {
      if (shippingLabelUrl !== null && typeof shippingLabelUrl !== 'string') fail(400, 'Enter a valid shipping label link.');
      if (shippingLabelUrl) {
        try {
          if (!['http:', 'https:'].includes(new URL(shippingLabelUrl).protocol) || shippingLabelUrl.length > 2000) throw new Error();
        } catch {
          fail(400, 'Enter a secure HTTP or HTTPS shipping label link.');
        }
      }
    }
    if (deliveryMethod !== undefined && !marketplaceDeliveryMethods.includes(deliveryMethod)) fail(400, 'Choose a valid delivery method.');
    for (const evidence of [shipmentEvidence, deliveryEvidence, statusReason]) if (evidence != null && !validText(evidence, 500)) fail(400, 'Record a concise reason or evidence reference.');
    const lineItemsChanged = [productCostMinor, shippingCostMinor, pickupFeeMinor, handlingFeeMinor].some(value => value !== undefined);
    const quoteChanged = amountMinor !== undefined || lineItemsChanged;
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const existing = await tx.serviceOrder.findFirst({ where: { id: req.params.id, organizationId: req.organizationId }, include: { marketplaceIssues: true, parcel: { select: { status: true, deliveryProofReference: true } } } });
      if (!existing) fail(404, 'Order not found.');
      const data = {};
      if (deliveryMethod !== undefined) {
        if (existing.kind !== 'MARKETPLACE' || !['REQUESTED', 'ACCEPTED'].includes(existing.status) || existing.paymentStatus === 'VERIFIED') fail(409, 'Delivery method is locked after payment or fulfillment starts.');
        const product = existing.productId ? await tx.product.findUnique({ where: { id: existing.productId }, include: { seller: { select: { commissionBps: true, localDeliveryEnabled: true, country: true } } } }) : null;
        if (deliveryMethod === 'D2F_DELIVERY' && product?.seller && (!product.seller.localDeliveryEnabled ||
          (existing.deliveryCountry && existing.deliveryCountry.toLowerCase() !== product.seller.country.toLowerCase()))) fail(409, 'D2F local delivery is unavailable for this seller and destination.');
        data.deliveryMethod = deliveryMethod;
        data.deliveryPreference = deliveryMethod === 'D2F_DELIVERY' ? 'D2F' : 'SELLER';
        if (product) {
          const fees = calculateFees(existing.amountMinor, { seller: product.seller, deliveryPreference: data.deliveryPreference, fulfillment: product.fulfillment, settings: await tx.commissionSettings.findFirst() });
          // Preserve the agreed commission and fulfillment snapshots.
          data.deliveryFeeBps = fees.deliveryFeeBps;
          data.deliveryFeeMinor = fees.deliveryFeeMinor;
          data.sellerNetMinor = Math.max(0, existing.amountMinor - (existing.commissionMinor || 0) - (existing.fulfillmentFeeMinor || 0) - fees.deliveryFeeMinor);
        }
      }
      if (status !== undefined) {
        if (!transitions[existing.kind][existing.status]?.includes(status)) fail(409, 'Invalid status change. Refresh this order.');
        if (existing.kind === 'BUY_FOR_ME' && status === 'PAYMENT_CONFIRMED') fail(409, 'Verify the submitted payment evidence before confirming payment.');
        if (existing.kind === 'BUY_FOR_ME' && existing.source === 'APP' && status === 'PURCHASED' && existing.paymentStatus !== 'VERIFIED') fail(409, 'Verify the customer payment before marking this item purchased.');
        if (existing.kind === 'MARKETPLACE') {
          if (['PROCESSING', 'SHIPPED', 'DELIVERED', 'COMPLETED'].includes(status)) requirePaid(existing);
          if (['FAILED_DELIVERY', 'CANCELLED'].includes(status) && !statusReason) fail(400, 'Record why this order failed or was cancelled.');
          if (status === 'COMPLETED' && !existing.deliveryConfirmedAt) fail(409, 'Confirm delivery from verified evidence first.');
          if (status === 'ACCEPTED' && !existing.marketplaceInvoice) data.marketplaceInvoice = await marketplaceInvoice(tx, existing);
        }
        data.status = status;
      }
      if (amountMinor !== undefined) {
        if (existing.kind !== 'BUY_FOR_ME' || !['REQUESTED', 'QUOTED'].includes(existing.status)) fail(409, 'Accepted quotes and marketplace price snapshots cannot be changed.');
        data.amountMinor = amountMinor;
      }
      if (lineItemsChanged) {
        if (existing.kind !== 'BUY_FOR_ME' || !['REQUESTED', 'QUOTED'].includes(existing.status)) fail(409, 'Accepted quotes cannot be changed.');
        data.productCostMinor = productCostMinor ?? existing.productCostMinor;
        data.shippingCostMinor = shippingCostMinor ?? existing.shippingCostMinor;
        data.pickupFeeMinor = pickupFeeMinor ?? existing.pickupFeeMinor;
        data.handlingFeeMinor = handlingFeeMinor ?? existing.handlingFeeMinor;
        const total = data.productCostMinor + data.shippingCostMinor + data.pickupFeeMinor + data.handlingFeeMinor;
        if (data.productCostMinor == null || data.shippingCostMinor == null || !validAmount(total)) {
          fail(400, 'Enter both product and shipping costs within the supported total.');
        }
        data.amountMinor = total;
      } else if (amountMinor !== undefined && existing.kind === 'BUY_FOR_ME') {
        data.productCostMinor = amountMinor;
        data.shippingCostMinor = 0;
        data.pickupFeeMinor = 0;
        data.handlingFeeMinor = 0;
      }
      if (status === 'QUOTED' && (
        (data.amountMinor ?? existing.amountMinor) === null ||
        (data.productCostMinor ?? existing.productCostMinor) == null ||
        (data.shippingCostMinor ?? existing.shippingCostMinor) == null
      )) fail(400, 'Record product and shipping costs before sending the quote.');
      if (trackingId !== undefined) {
        const parcel = await tx.parcel.findFirst({ where: { trackingId: trackingId.trim().toUpperCase(), customerId: existing.customerId, organizationId: req.organizationId } });
        if (!parcel) fail(400, 'Choose a parcel belonging to this customer and organization.');
        data.parcelId = parcel.id;
      }
      if (trackingRef !== undefined) data.trackingRef = trackingRef.trim() || null;
      if (deliveryService !== undefined) data.deliveryService = deliveryService;
      if (shippingCarrier !== undefined) data.shippingCarrier = shippingCarrier?.trim() || null;
      if (shippingTrackingNumber !== undefined) data.shippingTrackingNumber = shippingTrackingNumber?.trim() || null;
      if (shippingLabelUrl !== undefined) data.shippingLabelUrl = shippingLabelUrl?.trim() || null;
      if (existing.kind === 'MARKETPLACE' && shipmentEvidence) data.shipmentEvidence = shipmentEvidence.trim();
      if (status === 'DELIVERED' && existing.kind === 'MARKETPLACE') {
        if (data.parcelId && data.parcelId !== existing.parcelId) fail(409, 'Verify the recorded shipment before confirming delivery.');
        if (marketplaceDeliveryMethod(existing) === 'D2F_DELIVERY') {
          if (existing.parcel?.status !== 'DELIVERED' || !existing.parcel.deliveryProofReference) fail(409, 'Confirm recipient delivery with proof in D2F shipment tracking first.');
          data.deliveryEvidence = `D2F parcel ${existing.parcelId} · ${existing.parcel.deliveryProofReference}`;
        } else {
          if (!deliveryEvidence) fail(400, 'Record the verified carrier event, signed handover or pickup confirmation reference.');
          data.deliveryEvidence = deliveryEvidence.trim();
        }
        data.deliveryConfirmedAt = new Date();
        data.deliveryConfirmedById = req.user.id;
      }
      const effectiveTrackingRef = data.trackingRef !== undefined ? data.trackingRef : existing.trackingRef;
      if (status === 'SHIPPED' && existing.kind === 'MARKETPLACE') {
        deliveryRequirement({ ...existing, ...data }, {
          carrier: data.shippingCarrier ?? existing.shippingCarrier, externalRef: effectiveTrackingRef,
          parcelId: data.parcelId ?? existing.parcelId, shipmentEvidence: data.shipmentEvidence ?? existing.shipmentEvidence,
        });
      }
      if (status === 'SHIPPED' && existing.kind === 'BUY_FOR_ME') {
        if (!(data.parcelId || existing.parcelId || data.shippingTrackingNumber || existing.shippingTrackingNumber || effectiveTrackingRef)) fail(400, 'Add shipment tracking before marking this order shipped.');
        if (!(data.deliveryService || existing.deliveryService)) fail(400, 'Choose a D2F delivery option before marking this request shipped.');
      }
      if (notes !== undefined) data.notes = notes.trim() || null;
      if (!Object.keys(data).length && customerMessage === undefined) fail(400, 'No changes provided.');
      if (status === 'CANCELLED' && existing.status !== 'CANCELLED') {
        if (existing.kind === 'MARKETPLACE' && existing.paymentStatus === 'VERIFIED' && !existing.marketplaceIssues.some(issue => issue.type === 'REFUND' && issue.status === 'OPEN') && await refundTotal(tx, existing.id) < existing.amountMinor) {
          await openOrderIssue(tx, req, existing, { type: 'REFUND', reason: statusReason });
        }
        if (existing.status !== 'FAILED_DELIVERY') await releaseStock(tx, existing.productId, existing.quantity);
      }
      const updated = await tx.serviceOrder.update({ where: { id: existing.id }, data, include: orderInclude });
      await audit(tx, req, 'ServiceOrder', existing.id, 'SERVICE_ORDER_UPDATE', JSON.stringify({ from: existing.status, to: data.status || existing.status, reason: statusReason || undefined, ...data }));
      if (existing.kind === 'BUY_FOR_ME' && (customerMessage || status || deliveryService || shippingTrackingNumber || shippingLabelUrl || quoteChanged)) {
        await tx.serviceOrderUpdate.create({
          data: {
            serviceOrderId: existing.id,
            actorId: req.user.id,
            status: status || null,
            message: customerMessage?.trim() || (status ? `Your request is now ${status.toLowerCase().replaceAll('_', ' ')}.` : quoteChanged ? 'D2F updated your quote.' : 'D2F updated your delivery details.'),
            deliveryService: data.deliveryService ?? updated.deliveryService,
            shippingCarrier: data.shippingCarrier ?? updated.shippingCarrier,
            shippingTrackingNumber: data.shippingTrackingNumber ?? updated.shippingTrackingNumber,
            shippingLabelUrl: data.shippingLabelUrl ?? updated.shippingLabelUrl,
          },
        });
      }
      return updated;
    });
    res.json(result);
  } catch (e) { next(e); }
});

// ── Product approval workflow ───────────────────────────────────────────

router.post('/orders/:id/marketplace-payment', async (req, res, next) => {
  try {
    const { verified, method, reference, amountMinor, currency, note } = req.body || {};
    if (typeof verified !== 'boolean' || !validText(reference, 120) || !['BANK_TRANSFER', 'MOBILE_MONEY', 'CASH', 'CARD'].includes(method) ||
      (!verified && !validText(note, 500)) || !validOptionalText(note, 500)) fail(400, 'Record the payment method, transaction reference and any rejection reason.');
    const updated = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const order = await tx.serviceOrder.findFirst({ where: { id: req.params.id, organizationId: req.organizationId, kind: 'MARKETPLACE' } });
      if (!order) fail(404, 'Marketplace order not found.');
      if (order.status !== 'ACCEPTED' || order.paymentStatus === 'VERIFIED') fail(409, 'Only an accepted order awaiting payment can be reviewed.');
      if (verified && (amountMinor !== order.amountMinor || currency !== order.currency)) fail(400, 'Verified amount and currency must match the order total.');
      if (verified && await tx.serviceOrder.count({ where: { organizationId: req.organizationId, kind: 'MARKETPLACE', marketplacePaymentMethod: method, paymentTransactionId: reference.trim(), paymentStatus: 'VERIFIED', id: { not: order.id } } })) fail(409, 'This payment reference is already recorded for another order.');
      const data = { paymentStatus: verified ? 'VERIFIED' : 'REJECTED', paymentTransactionId: reference.trim(), marketplacePaymentMethod: method,
        marketplacePaymentNote: note?.trim() || null, marketplacePaymentVerifiedAt: new Date(), marketplacePaymentVerifiedById: req.user.id };
      if (order.paymentStatus === data.paymentStatus && order.paymentTransactionId === data.paymentTransactionId && order.marketplacePaymentNote === data.marketplacePaymentNote) fail(409, 'This review has already been recorded.');
      const result = await tx.serviceOrder.update({ where: { id: order.id }, data, include: orderInclude });
      await audit(tx, req, 'ServiceOrder', order.id, `MARKETPLACE_PAYMENT_${data.paymentStatus}`, JSON.stringify({ from: order.paymentStatus, to: data.paymentStatus, method, amountMinor, currency, reference, reason: data.marketplacePaymentNote }));
      await marketplaceNotice(tx, order, `ORDER_PAYMENT_${data.paymentStatus}`, verified ? 'Payment verified' : `Payment rejected. ${note.trim()}`);
      return result;
    });
    res.json(updated);
  } catch (e) { next(e); }
});

router.get('/orders/:id/history', async (req, res, next) => {
  try {
    const order = await prisma.serviceOrder.findFirst({ where: { id: req.params.id, organizationId: req.organizationId, kind: 'MARKETPLACE' }, select: { id: true } });
    if (!order) fail(404, 'Marketplace order not found.');
    const rows = await prisma.auditLog.findMany({ where: { entity: 'ServiceOrder', entityId: order.id }, orderBy: { createdAt: 'desc' }, take: 100 });
    const actors = await prisma.user.findMany({ where: { id: { in: [...new Set(rows.map(row => row.actorId).filter(Boolean))] } }, select: { id: true, fullName: true, role: true } });
    const actorById = new Map(actors.map(actor => [actor.id, actor]));
    res.json(rows.map(row => ({ ...row, actor: actorById.get(row.actorId) ?? null })));
  } catch (e) { next(e); }
});

router.post('/orders/:id/issues', async (req, res, next) => {
  try {
    const issue = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const order = await tx.serviceOrder.findFirst({ where: { id: req.params.id, organizationId: req.organizationId, kind: 'MARKETPLACE' }, include: { marketplaceIssues: true } });
      if (!order) fail(404, 'Marketplace order not found.');
      return openOrderIssue(tx, req, order, req.body);
    });
    res.status(201).json(issue);
  } catch (e) { next(e); }
});

router.patch('/orders/:id/issues/:issueId', async (req, res, next) => {
  try {
    const { status, resolution, amountMinor, reference } = req.body || {};
    if (!['RESOLVED', 'DECLINED'].includes(status) || !validText(resolution, 1000)) fail(400, 'Choose a resolution and record the outcome.');
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const order = await tx.serviceOrder.findFirst({ where: { id: req.params.id, organizationId: req.organizationId, kind: 'MARKETPLACE' }, include: { marketplaceIssues: true } });
      if (!order) fail(404, 'Marketplace order not found.');
      const issue = order.marketplaceIssues.find(row => row.id === req.params.issueId);
      if (issue?.status !== 'OPEN') fail(409, 'This issue is no longer open.');
      const refund = issue.type === 'REFUND' && status === 'RESOLVED';
      if (refund) {
        if (!validText(reference, 120) || !validAmount(amountMinor) || amountMinor <= 0) fail(400, 'Record the confirmed refund amount and external transaction reference.');
        if (order.paymentStatus !== 'VERIFIED' || await refundTotal(tx, order.id) + amountMinor > order.amountMinor) fail(409, 'Refund exceeds the verified payment remaining.');
        if (await tx.marketplaceOrderIssue.count({ where: { type: 'REFUND', status: 'RESOLVED', evidence: reference.trim(), order: { organizationId: req.organizationId } } })) fail(409, 'This external refund has already been recorded.');
      }
      const saved = await tx.marketplaceOrderIssue.update({ where: { id: issue.id }, data: { status, resolution: resolution.trim(), resolvedById: req.user.id, resolvedAt: new Date(), ...(refund ? { amountMinor, evidence: reference.trim() } : {}) } });
      await audit(tx, req, 'ServiceOrder', order.id, 'MARKETPLACE_ISSUE_CLOSED', JSON.stringify({ issueId: issue.id, type: issue.type, from: issue.status, to: status, amountMinor: saved.amountMinor, resolution }));
      await marketplaceNotice(tx, order, `ORDER_${issue.type}_${status}`, `${issue.type.toLowerCase()} request ${status.toLowerCase()}. ${resolution.trim()}`);
      return saved;
    });
    res.json(result);
  } catch (e) { next(e); }
});

router.get('/products/pending', async (req, res, next) => {
  try {
    const products = await prisma.product.findMany({
      where: { organizationId: req.organizationId, status: 'PENDING_REVIEW' },
      include: { seller: { select: { id: true, displayName: true, status: true } } },
      orderBy: { createdAt: 'asc' },
      take: 200,
    });
    res.json(products);
  } catch (e) { next(e); }
});

router.post('/products/:id/approve', async (req, res, next) => {
  try {
    const { action, reviewNote } = req.body || {};
    if (!['APPROVE', 'REJECT'].includes(action)) fail(400, 'Choose approve or reject.');
    const product = await prisma.product.findFirst({ where: { id: req.params.id, organizationId: req.organizationId } });
    if (!product) fail(404, 'Product not found.');
    if (product.status !== 'PENDING_REVIEW') fail(409, `Product is already ${product.status.toLowerCase()}.`);
    const updated = await prisma.$transaction(async (tx) => {
      const result = await tx.product.update({
        where: { id: product.id },
        data: { status: action === 'APPROVE' ? 'APPROVED' : 'REJECTED', isActive: action === 'APPROVE', reviewNote: reviewNote?.trim() || null },
        include: { seller: { select: { id: true, displayName: true, userId: true } } },
      });
      await audit(tx, req, 'Product', product.id, action === 'APPROVE' ? 'PRODUCT_APPROVE' : 'PRODUCT_REJECT', reviewNote || `${product.status} → ${action}`);
      return result;
    });
    res.json(updated);
  } catch (e) { next(e); }
});

// ── Commission settings (global D2F config) ─────────────────────────────

router.get('/commission-settings', async (req, res, next) => {
  try {
    let settings = await prisma.commissionSettings.findFirst();
    if (!settings) {
      settings = await prisma.commissionSettings.create({
        data: { platformCommissionBps: 1000, defaultFulfillmentFeeBps: 500, defaultDeliveryFeeBps: 300 },
      });
    }
    res.json(settings);
  } catch (e) { next(e); }
});

router.post('/commission-settings', async (req, res, next) => {
  try {
    const { platformCommissionBps, defaultFulfillmentFeeBps, defaultDeliveryFeeBps } = req.body || {};
    if (platformCommissionBps !== undefined && !validBps(platformCommissionBps)) fail(400, 'Platform commission must be between 0% and 50%.');
    if (defaultFulfillmentFeeBps !== undefined && !validBps(defaultFulfillmentFeeBps)) fail(400, 'Fulfillment fee must be between 0% and 50%.');
    if (defaultDeliveryFeeBps !== undefined && !validBps(defaultDeliveryFeeBps)) fail(400, 'Delivery fee must be between 0% and 50%.');
    let settings = await prisma.commissionSettings.findFirst();
    if (!settings) {
      settings = await prisma.commissionSettings.create({
        data: {
          platformCommissionBps: platformCommissionBps ?? 1000,
          defaultFulfillmentFeeBps: defaultFulfillmentFeeBps ?? 500,
          defaultDeliveryFeeBps: defaultDeliveryFeeBps ?? 300,
          updatedById: req.user.id,
        },
      });
    } else {
      settings = await prisma.commissionSettings.update({
        where: { id: settings.id },
        data: {
          ...(platformCommissionBps !== undefined && { platformCommissionBps }),
          ...(defaultFulfillmentFeeBps !== undefined && { defaultFulfillmentFeeBps }),
          ...(defaultDeliveryFeeBps !== undefined && { defaultDeliveryFeeBps }),
          updatedById: req.user.id,
        },
      });
    }
    await audit(prisma, req, 'CommissionSettings', settings.id, 'COMMISSION_SETTINGS_UPDATE', JSON.stringify({ platformCommissionBps, defaultFulfillmentFeeBps, defaultDeliveryFeeBps }));
    res.json(settings);
  } catch (e) { next(e); }
});

// ── Seller earnings ─────────────────────────────────────────────────────

router.get('/sellers/:id/earnings', async (req, res, next) => {
  try {
    const sellerId = req.params.id;
    const profile = await prisma.sellerProfile.findFirst({ where: { id: sellerId, organizationId: req.organizationId } });
    if (!profile) fail(404, 'Seller not found.');
    const earnings = await prisma.sellerEarnings.findUnique({ where: { sellerId } });
    // Recalculate from completed orders
    const orders = await prisma.serviceOrder.findMany({
      where: { sellerId, kind: 'MARKETPLACE', status: 'COMPLETED', paymentStatus: 'VERIFIED', deliveryConfirmedAt: { not: null } },
      select: { amountMinor: true, commissionMinor: true, fulfillmentFeeMinor: true, deliveryFeeMinor: true, sellerNetMinor: true, currency: true },
    });
    const totals = orders.reduce((acc, o) => {
      acc.gross += o.amountMinor ?? 0;
      acc.commission += o.commissionMinor ?? 0;
      acc.fulfillment += o.fulfillmentFeeMinor ?? 0;
      acc.delivery += o.deliveryFeeMinor ?? 0;
      acc.net += o.sellerNetMinor ?? 0;
      return acc;
    }, { gross: 0, commission: 0, fulfillment: 0, delivery: 0, net: 0 });
    res.json({ sellerId, displayName: profile.displayName, earnings, totals, orderCount: orders.length });
  } catch (e) { next(e); }
});

// ── Payouts ─────────────────────────────────────────────────────────────

router.get('/payouts', async (req, res, next) => {
  try {
    const status = typeof req.query.status === 'string' ? req.query.status.toUpperCase() : null;
    const payouts = await prisma.sellerPayout.findMany({
      where: { ...(status ? { status } : {}), seller: { organizationId: req.organizationId } },
      include: { seller: { select: { id: true, displayName: true, status: true } } },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
    res.json(payouts);
  } catch (e) { next(e); }
});

router.post('/payouts', async (req, res, next) => {
  try {
    const { sellerId, amountMinor, currency = 'USD', reference } = req.body || {};
    if (typeof sellerId !== 'string') fail(400, 'Choose a seller.');
    if (!validAmount(amountMinor) || amountMinor <= 0) fail(400, 'Enter a valid payout amount.');
    const seller = await prisma.sellerProfile.findFirst({ where: { id: sellerId, organizationId: req.organizationId } });
    if (!seller) fail(404, 'Seller not found.');
    if (!currencies.includes(currency) || !validText(reference, 120)) fail(400, 'Enter the payout currency and confirmed transfer reference.');
    const payout = await prisma.$transaction(async (tx) => {
      await warehouseLock(tx, req.organizationId);
      if (seller.status !== 'APPROVED') fail(409, 'Payouts are suspended for this seller.');
      if (await tx.sellerPayout.count({ where: { sellerId, currency, reference: reference.trim() } })) fail(409, 'This payout reference was already recorded.');
      if (await payableBalance(tx, sellerId, currency) < amountMinor) fail(409, 'Insufficient verified payable balance in this currency.');
      const created = await tx.sellerPayout.create({
        data: { sellerId, amountMinor, currency, status: 'PAID', paidAt: new Date(), reference: reference?.trim() || null },
      });
      await tx.sellerEarnings.updateMany({ where: { sellerId }, data: { paidOutMinor: { increment: amountMinor } } });
      await audit(tx, req, 'SellerPayout', created.id, 'SELLER_PAYOUT', `paid ${amountMinor} ${currency} to ${seller.displayName}`);
      return created;
    });
    res.status(201).json(payout);
  } catch (e) { next(e); }
});

export default router;
