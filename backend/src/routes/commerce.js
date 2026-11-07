import { Router, raw } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { resolveOrganizationId } from '../tracking.js';
import { fail, warehouseLock } from '../warehouse.js';
import { commissionFor, releaseStock, validOptionalText } from '../shopfront.js';
import { createNotification } from '../notifications.js';
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
  MARKETPLACE: { REQUESTED: ['ACCEPTED', 'CANCELLED'], ACCEPTED: ['PROCESSING', 'CANCELLED'], PROCESSING: ['SHIPPED', 'CANCELLED'], SHIPPED: ['COMPLETED'], COMPLETED: [], CANCELLED: [] },
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
      orderBy: [{ status: 'asc' }, { createdAt: 'desc' }],
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
      if (rule.to === 'APPROVED') {
        const sellerUser = await tx.user.findUnique({ where: { id: existing.userId }, select: { id: true, fullName: true } });
        if (sellerUser) {
          await createNotification({
            userId: sellerUser.id,
            type: 'SELLER_APPROVED',
            title: 'Your D2F seller account is approved',
            body: data.commissionBps != null ? `Commission agreed at ${(data.commissionBps / 100).toFixed(2)}%. You can now publish your listings.` : 'You can now publish your listings.',
          });
        }
      }
      return updated;
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
        ? orders.map(order => ({ ...order, paymentInstructions: `Zelle: ${process.env.D2F_ZELLE_ACCOUNT || '01234567'}` }))
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
    if (result.order.customer?.id) {
      const customer = await prisma.customer.findUnique({ where: { id: result.order.customer.id }, select: { userId: true } });
      if (customer?.userId) {
        await createNotification({
          userId: customer.userId,
          type: accepted ? 'BUY_FOR_ME_PAYMENT_VERIFIED' : 'BUY_FOR_ME_PAYMENT_REJECTED',
          title: accepted ? 'Payment confirmed' : 'Payment needs attention',
          body: accepted
            ? 'D2F verified your payment and will now purchase your item.'
            : `Please review your payment proof: ${note.trim()}`,
        });
      }
    }
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
    const customer = await prisma.customer.findUnique({ where: { id: result.order.customer.id }, select: { userId: true } });
    if (customer?.userId) {
      await createNotification({
        userId: customer.userId,
        type: 'BUY_FOR_ME_UPDATE',
        title: 'New update on your Buy For Me request',
        body: message?.trim() || `D2F updated your request${status ? ` to ${status.toLowerCase().replaceAll('_', ' ')}` : ''}.`,
      });
    }
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
    const { kind, customerId, productId, title, sourceUrl, quantity = 1, currency = 'USD', notes } = req.body || {};
    if (!transitions[kind] || typeof customerId !== 'string' || !Number.isSafeInteger(quantity) || quantity < 1 || quantity > 1000 || !currencies.includes(currency) || (notes != null && !validText(notes, 2000))) fail(400, 'Choose a customer, module, currency and valid quantity.');
    if (kind === 'BUY_FOR_ME' && !validText(title)) fail(400, 'Describe the requested item.');
    if (sourceUrl != null && typeof sourceUrl !== 'string') fail(400, 'Enter a valid product link.');
    if (sourceUrl) { try { if (!['http:', 'https:'].includes(new URL(sourceUrl).protocol) || sourceUrl.length > 2000) throw new Error(); } catch { fail(400, 'Enter a valid HTTP or HTTPS product link.'); } }
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      if (!await tx.customer.findFirst({ where: { id: customerId, organizationId: req.organizationId } })) fail(404, 'Customer not found.');
      let product;
      if (kind === 'MARKETPLACE') {
        if (typeof productId !== 'string') fail(400, 'Choose an available product.');
        product = await tx.product.findFirst({ where: { id: productId, organizationId: req.organizationId, isActive: true }, include: { seller: { select: { id: true, commissionBps: true } } } });
        if (!product) fail(400, 'Choose an available product.');
        if (!validAmount(product.priceMinor * quantity)) fail(400, 'Order total is too large.');
      }
      const created = await tx.serviceOrder.create({ data: { organizationId: req.organizationId, kind, customerId,
        productId: product?.id, sellerId: product?.sellerId ?? null, title: product?.title || title.trim(), sourceUrl: sourceUrl || null,
        quantity, currency: product?.currency || currency, amountMinor: product ? product.priceMinor * quantity : null, notes: notes?.trim() || null,
        source: 'ADMIN',
        ...(product ? commissionFor(product.priceMinor * quantity, product.seller) : {}) }, include: orderInclude });
      await audit(tx, req, 'ServiceOrder', created.id, 'SERVICE_ORDER_CREATE', `${kind}: ${created.title}`);
      return created;
    });
    res.status(201).json(result);
  } catch (e) { next(e); }
});
router.patch('/orders/:id', async (req, res, next) => {
  try {
    const {
      status, amountMinor, productCostMinor, shippingCostMinor, trackingId, notes, trackingRef,
      deliveryService, shippingCarrier, shippingTrackingNumber, shippingLabelUrl, customerMessage,
    } = req.body || {};
    if (amountMinor !== undefined && !validAmount(amountMinor)) fail(400, 'Enter a valid quote total.');
    if (productCostMinor !== undefined && !validAmount(productCostMinor)) fail(400, 'Enter a valid product cost.');
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
    const quoteChanged = amountMinor !== undefined || productCostMinor !== undefined || shippingCostMinor !== undefined;
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const existing = await tx.serviceOrder.findFirst({ where: { id: req.params.id, organizationId: req.organizationId } });
      if (!existing) fail(404, 'Order not found.');
      const data = {};
      if (status !== undefined) {
        if (!transitions[existing.kind][existing.status]?.includes(status)) fail(409, 'Invalid status change. Refresh this order.');
        if (existing.kind === 'BUY_FOR_ME' && status === 'PAYMENT_CONFIRMED') fail(409, 'Verify the submitted payment evidence before confirming payment.');
        if (existing.kind === 'BUY_FOR_ME' && existing.source === 'APP' && status === 'PURCHASED' && existing.paymentStatus !== 'VERIFIED') fail(409, 'Verify the customer payment before marking this item purchased.');
        data.status = status;
      }
      if (amountMinor !== undefined) {
        if (existing.kind !== 'BUY_FOR_ME' || !['REQUESTED', 'QUOTED'].includes(existing.status)) fail(409, 'Accepted quotes and marketplace price snapshots cannot be changed.');
        data.amountMinor = amountMinor;
      }
      if (productCostMinor !== undefined || shippingCostMinor !== undefined) {
        if (existing.kind !== 'BUY_FOR_ME' || !['REQUESTED', 'QUOTED'].includes(existing.status)) fail(409, 'Accepted quotes cannot be changed.');
        data.productCostMinor = productCostMinor ?? existing.productCostMinor;
        data.shippingCostMinor = shippingCostMinor ?? existing.shippingCostMinor;
        if (data.productCostMinor == null || data.shippingCostMinor == null || !validAmount(data.productCostMinor + data.shippingCostMinor)) {
          fail(400, 'Enter both product and shipping costs within the supported total.');
        }
        data.amountMinor = data.productCostMinor + data.shippingCostMinor;
      } else if (amountMinor !== undefined && existing.kind === 'BUY_FOR_ME') {
        data.productCostMinor = amountMinor;
        data.shippingCostMinor = 0;
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
      const effectiveTrackingRef = data.trackingRef !== undefined ? data.trackingRef : existing.trackingRef;
      if (status === 'SHIPPED') {
        const appOrder = existing.kind === 'MARKETPLACE' && existing.source === 'APP';
        // D2F-fulfilled orders link a parcel; seller-shipped app orders may
        // carry the seller's carrier reference instead.
        const hasProof = data.parcelId || existing.parcelId ||
          (existing.kind === 'BUY_FOR_ME' && (data.shippingTrackingNumber || existing.shippingTrackingNumber || effectiveTrackingRef)) ||
          (appOrder && effectiveTrackingRef);
        if (!hasProof) fail(400, appOrder || existing.kind === 'BUY_FOR_ME' ? 'Add shipment tracking before marking this order shipped.' : 'Link the customer’s parcel before marking it shipped.');
        if (existing.kind === 'BUY_FOR_ME' && !(data.deliveryService || existing.deliveryService)) fail(400, 'Choose a D2F delivery option before marking this request shipped.');
      }
      if (notes !== undefined) data.notes = notes.trim() || null;
      if (!Object.keys(data).length && customerMessage === undefined) fail(400, 'No changes provided.');
      if (status === 'CANCELLED' && existing.status !== 'CANCELLED') await releaseStock(tx, existing.productId, existing.quantity);
      const updated = await tx.serviceOrder.update({ where: { id: existing.id }, data, include: orderInclude });
      await audit(tx, req, 'ServiceOrder', existing.id, 'SERVICE_ORDER_UPDATE', JSON.stringify({ from: existing.status, ...data }));
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
    const quoteIsReady = result.kind === 'BUY_FOR_ME' && result.status === 'QUOTED' && (status === 'QUOTED' || quoteChanged);
    if (result.kind === 'BUY_FOR_ME' && (quoteIsReady || status)) {
      const customer = await prisma.customer.findUnique({ where: { id: result.customer.id }, select: { userId: true } });
      if (customer?.userId) {
        await createNotification({
          userId: customer.userId,
          type: quoteIsReady ? 'BUY_FOR_ME_QUOTED' : 'BUY_FOR_ME_UPDATE',
          title: quoteIsReady ? 'Your Buy For Me quote is ready' : 'Your Buy For Me request was updated',
          body: quoteIsReady
            ? `D2F quoted ${result.title} at ${result.currency} ${((result.amountMinor || 0) / (result.currency === 'XOF' ? 1 : 100)).toFixed(result.currency === 'XOF' ? 0 : 2)}. Respond now in the app.`
            : customerMessage?.trim() || `Your request status is now ${status.toLowerCase().replaceAll('_', ' ')}.`,
        });
      }
    }
    res.json(result);
  } catch (e) { next(e); }
});

// ── Product approval workflow ───────────────────────────────────────────

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
    // Notify the seller
    if (updated.seller?.userId) {
      await createNotification({
        userId: updated.seller.userId,
        type: action === 'APPROVE' ? 'PRODUCT_APPROVED' : 'PRODUCT_REJECTED',
        title: action === 'APPROVE' ? 'Product approved' : 'Product rejected',
        body: action === 'APPROVE' ? `${product.title} is now live on the marketplace.` : `Product "${product.title}" was not approved. ${reviewNote || ''}`,
      });
    }
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
      where: { sellerId, kind: 'MARKETPLACE', status: 'COMPLETED' },
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
    const earnings = await prisma.sellerEarnings.findUnique({ where: { sellerId } });
    if (!earnings || earnings.netPayableMinor < amountMinor) fail(400, 'Insufficient payable balance.');
    const payout = await prisma.$transaction(async (tx) => {
      const created = await tx.sellerPayout.create({
        data: { sellerId, amountMinor, currency, status: 'PAID', paidAt: new Date(), reference: reference?.trim() || null },
      });
      await tx.sellerEarnings.update({
        where: { sellerId },
        data: { paidOutMinor: earnings.paidOutMinor + amountMinor },
      });
      await audit(tx, req, 'SellerPayout', created.id, 'SELLER_PAYOUT', `paid ${amountMinor} ${currency} to ${seller.displayName}`);
      return created;
    });
    res.status(201).json(payout);
  } catch (e) { next(e); }
});

export default router;
