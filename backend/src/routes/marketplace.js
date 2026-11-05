// D2F Marketplace — customer-facing browse and order flow.
// Every sale through the app is an order REQUEST the seller (or D2F)
// confirms; payment is coordinated offline, so no card data ever touches
// this API. Commission is agreed at seller approval and snapshotted here.

import { Router, raw } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { fail, warehouseLock } from '../warehouse.js';
import { resolveOrganizationId } from '../tracking.js';
import {
  audit,
  commissionFor,
  calculateFees,
  customerOrderSelect,
  currencies,
  deliveryPreferences,
  reserveStock,
  releaseStock,
  upsertCustomer,
  validAmount,
  validOptionalText,
  validText,
} from '../shopfront.js';
import { createNotification } from '../notifications.js';

const router = Router();
router.use(authenticate);

const ORDER_PAGE_SIZE = 30;

const imageMetaSelect = {
  id: true,
  fileName: true,
  contentType: true,
  sizeBytes: true,
  position: true,
  createdAt: true,
};

// Visibility rule: D2F catalog products and listings from APPROVED sellers.
const visibilityWhere = {
  OR: [{ sellerId: null }, { seller: { status: 'APPROVED' } }],
};

const browseWhere = (organizationId) => ({
  organizationId,
  isActive: true,
  AND: [visibilityWhere],
});

const browseSelect = {
  id: true,
  title: true,
  category: true,
  description: true,
  priceMinor: true,
  currency: true,
  fulfillment: true,
  stockCount: true,
  locationCity: true,
  locationCountry: true,
  featured: true,
  createdAt: true,
  images: { orderBy: { position: 'asc' }, take: 1, select: { id: true } },
  seller: { select: { id: true, displayName: true, city: true, country: true } },
};

const withAvailability = (product) => ({
  ...product,
  soldOut: product.stockCount != null && product.stockCount <= 0,
});

// ── Browse ───────────────────────────────────────────────────────────────────

router.get('/products', async (req, res, next) => {
  try {
    const organizationId = await resolveShopOrganization(req);
    const q = typeof req.query.q === 'string' ? req.query.q.trim().slice(0, 80) : '';
    const category = typeof req.query.category === 'string' ? req.query.category.trim().slice(0, 80) : '';
    const country = typeof req.query.country === 'string' ? req.query.country.trim().slice(0, 80) : '';
    const featuredOnly = req.query.featured === 'true';
    const page = Number(req.query.page ?? 1);
    const limit = Number(req.query.limit ?? 24);
    if (!Number.isSafeInteger(page) || page < 1 || !Number.isSafeInteger(limit) || limit < 1 || limit > 48) {
      fail(400, 'Invalid page.');
    }
    const where = {
      ...browseWhere(organizationId),
      AND: [
        visibilityWhere,
        ...(q ? [{ OR: [
          { title: { contains: q, mode: 'insensitive' } },
          { description: { contains: q, mode: 'insensitive' } },
          { category: { contains: q, mode: 'insensitive' } },
        ] }] : []),
      ],
      ...(category ? { category: { equals: category, mode: 'insensitive' } } : {}),
      ...(country ? { locationCountry: { equals: country, mode: 'insensitive' } } : {}),
      ...(featuredOnly ? { featured: true } : {}),
    };
    const skip = (page - 1) * limit;
    const [products, total, categories, countries] = await prisma.$transaction([
      prisma.product.findMany({
        where,
        select: browseSelect,
        orderBy: [{ featured: 'desc' }, { createdAt: 'desc' }, { id: 'asc' }],
        take: limit,
        skip,
      }),
      prisma.product.count({ where }),
      prisma.product.groupBy({
        by: ['category'],
        where: browseWhere(organizationId),
        _count: { category: true },
        orderBy: { _count: { category: 'desc' } },
        take: 24,
      }),
      prisma.product.groupBy({
        by: ['locationCountry'],
        where: { ...browseWhere(organizationId), locationCountry: { not: null } },
        _count: { locationCountry: true },
        orderBy: { _count: { locationCountry: 'desc' } },
        take: 24,
      }),
    ]);
    res.json({
      products: products.map(withAvailability),
      total,
      page,
      limit,
      categories: categories.map((row) => ({ name: row.category, count: row._count.category })),
      countries: countries
        .filter((row) => row.locationCountry)
        .map((row) => ({ name: row.locationCountry, count: row._count.locationCountry })),
    });
  } catch (error) {
    next(error);
  }
});

router.get('/products/:id', async (req, res, next) => {
  try {
    const organizationId = await resolveShopOrganization(req);
    const product = await prisma.product.findFirst({
      where: { id: req.params.id, ...browseWhere(organizationId) },
      select: {
        ...browseSelect,
        images: { orderBy: { position: 'asc' }, select: imageMetaSelect },
        seller: {
          select: {
            id: true,
            displayName: true,
            headline: true,
            city: true,
            country: true,
            category: true,
            createdAt: true,
          },
        },
      },
    });
    if (!product) fail(404, 'Product not found.');
    res.json(withAvailability(product));
  } catch (error) {
    next(error);
  }
});

router.get('/products/:id/images/:imageId/raw', async (req, res, next) => {
  try {
    const organizationId = await resolveShopOrganization(req);
    const image = await prisma.productImage.findFirst({
      where: { id: req.params.imageId, productId: req.params.id, product: browseWhere(organizationId) },
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

// ── Customer orders ──────────────────────────────────────────────────────────

router.get('/orders', requireRole('CUSTOMER'), async (req, res, next) => {
  try {
    const customer = await prisma.customer.findUnique({
      where: { userId: req.user.id },
      select: { id: true },
    });
    if (!customer) return res.json([]);
    const orders = await prisma.serviceOrder.findMany({
      where: { customerId: customer.id, kind: 'MARKETPLACE' },
      select: customerOrderSelect,
      orderBy: { createdAt: 'desc' },
      take: ORDER_PAGE_SIZE,
    });
    res.json(orders);
  } catch (error) {
    next(error);
  }
});

router.post('/orders', requireRole('CUSTOMER'), async (req, res, next) => {
  try {
    const {
      productId,
      quantity = 1,
      deliveryPreference = 'D2F',
      recipientName,
      recipientPhone,
      deliveryAddress,
      deliveryCity,
      deliveryCountry,
      notes,
    } = req.body || {};
    if (typeof productId !== 'string' || productId.length > 64) fail(400, 'Choose a product.');
    if (!Number.isSafeInteger(quantity) || quantity < 1 || quantity > 99) fail(400, 'Choose a quantity between 1 and 99.');
    if (!deliveryPreferences.includes(deliveryPreference)) fail(400, 'Choose how this order should reach you.');
    if (!validText(recipientPhone, 40) || !validText(deliveryAddress, 300) || !validText(deliveryCity, 120) || !validText(deliveryCountry, 120)) {
      fail(400, 'Tell us who receives the order and where it goes.');
    }
    if (recipientName != null && !validText(recipientName, 120)) fail(400, 'Enter a valid recipient name.');
    if (!validOptionalText(notes, 2000)) fail(400, 'Notes are too long.');

    const organizationId = await resolveShopOrganization(req);
    const order = await prisma.$transaction(async (tx) => {
      await warehouseLock(tx, organizationId);
      const customer = await upsertCustomer(tx, req.user);
      const product = await tx.product.findFirst({
        where: { id: productId, ...browseWhere(organizationId) },
        select: {
          id: true,
          title: true,
          priceMinor: true,
          currency: true,
          stockCount: true,
          seller: { select: { id: true, status: true, commissionBps: true, displayName: true } },
        },
      });
      if (!product) fail(404, 'That product is no longer available.');
      const amountMinor = product.priceMinor * quantity;
      if (!validAmount(amountMinor)) fail(400, 'Order total is too large.');
      if (!(await reserveStock(tx, product.id, quantity))) {
        fail(409, 'That product sold out. Reduce the quantity or try another listing.');
      }
      const settings = await prisma.commissionSettings.findFirst();
      const { commissionBps, commissionMinor, fulfillmentFeeBps, fulfillmentFeeMinor, deliveryFeeBps, deliveryFeeMinor, sellerNetMinor } = calculateFees(amountMinor, {
        seller: product.seller,
        deliveryPreference,
        fulfillment: product.fulfillment,
        settings,
      });
      const created = await tx.serviceOrder.create({
        data: {
          organizationId,
          kind: 'MARKETPLACE',
          customerId: customer.id,
          productId: product.id,
          sellerId: product.seller?.id ?? null,
          title: product.title,
          quantity,
          amountMinor,
          currency: product.currency,
          status: 'REQUESTED',
          source: 'APP',
          deliveryPreference,
          recipientName: recipientName?.trim() || req.user.fullName,
          recipientPhone: recipientPhone.trim(),
          deliveryAddress: deliveryAddress.trim(),
          deliveryCity: deliveryCity.trim(),
          deliveryCountry: deliveryCountry.trim(),
          notes: notes?.trim() || null,
          commissionBps,
          commissionMinor,
          fulfillmentFeeBps,
          fulfillmentFeeMinor,
          deliveryFeeBps,
          deliveryFeeMinor,
          sellerNetMinor,
        },
        select: customerOrderSelect,
      });
      await audit(tx, req, 'ServiceOrder', created.id, 'MARKETPLACE_ORDER_REQUEST', `${product.title} ×${quantity}`);
      return created;
    });
    if (order.seller?.id) {
      const seller = await prisma.sellerProfile.findUnique({ where: { id: order.seller.id }, select: { userId: true } });
      if (seller?.userId) {
        await createNotification({
          userId: seller.userId,
          type: 'ORDER_REQUESTED',
          title: 'New marketplace order request',
          body: `${order.product?.title ?? 'A product'} ×${order.quantity} is waiting for your response.`,
        });
      }
    }
    res.status(201).json(order);
  } catch (error) {
    next(error);
  }
});

router.post('/orders/:id/cancel', requireRole('CUSTOMER'), async (req, res, next) => {
  try {
    const result = await prisma.$transaction(async (tx) => {
      const customer = await tx.customer.findUnique({ where: { userId: req.user.id }, select: { id: true } });
      if (!customer) fail(404, 'Order not found.');
      const order = await tx.serviceOrder.findFirst({
        where: { id: req.params.id, customerId: customer.id, kind: 'MARKETPLACE' },
      });
      if (!order) fail(404, 'Order not found.');
      if (order.status !== 'REQUESTED') fail(409, 'The order is already being prepared — contact D2F to change or cancel it.');
      const updated = await tx.serviceOrder.update({
        where: { id: order.id },
        data: { status: 'CANCELLED' },
        select: customerOrderSelect,
      });
      await releaseStock(tx, order.productId, order.quantity);
      await audit(tx, req, 'ServiceOrder', order.id, 'MARKETPLACE_ORDER_CANCEL', 'cancelled by customer');
      return updated;
    });
    const sellerId = result.seller?.id;
    if (sellerId) {
      const seller = await prisma.sellerProfile.findUnique({ where: { id: sellerId }, select: { userId: true } });
      if (seller?.userId) {
        await createNotification({
          userId: seller.userId,
          type: 'ORDER_CANCELLED',
          title: 'Order cancelled',
          body: `${result.product?.title ?? 'A product'} ×${result.quantity} was cancelled by the buyer.`,
        });
      }
    }
    res.json(result);
  } catch (error) {
    next(error);
  }
});

// Customers can browse with any signed-in role but orders require a customer
// account; shop organization comes from the caller (linked or single active).
async function resolveShopOrganization(req) {
  const linked = await prisma.customer.findUnique({
    where: { userId: req.user.id },
    select: { organizationId: true },
  });
  return resolveOrganizationId(prisma, {
    ...req.user,
    organizationId: req.user.organizationId || linked?.organizationId,
  });
}

export default router;
