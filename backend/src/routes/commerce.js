import { Router } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { resolveOrganizationId } from '../tracking.js';
import { fail, warehouseLock } from '../warehouse.js';
const router = Router();
router.use(authenticate, requireRole('ADMIN'), async (req, res, next) => {
  try { req.organizationId = await resolveOrganizationId(prisma, req.user); next(); } catch (e) { next(e); }
});
const validText = (v, max = 200) => typeof v === 'string' && v.trim().length > 0 && v.length <= max;
const validAmount = v => Number.isSafeInteger(v) && v >= 0 && v <= 1000000000;
const currencies = ['USD', 'EUR', 'XOF'];
const orderInclude = { customer: { select: { id: true, displayName: true } }, product: { select: { title: true } }, parcel: { select: { trackingId: true, id: true } } };
const transitions = {
  MARKETPLACE: { REQUESTED: ['ACCEPTED', 'CANCELLED'], ACCEPTED: ['PROCESSING', 'CANCELLED'], PROCESSING: ['SHIPPED', 'CANCELLED'], SHIPPED: ['COMPLETED'], COMPLETED: [], CANCELLED: [] },
  BUY_FOR_ME: { REQUESTED: ['QUOTED', 'CANCELLED'], QUOTED: ['ACCEPTED', 'CANCELLED'], ACCEPTED: ['PURCHASED', 'CANCELLED'], PURCHASED: ['RECEIVED'], RECEIVED: ['SHIPPED'], SHIPPED: ['COMPLETED'], COMPLETED: [], CANCELLED: [] },
};
async function audit(tx, req, entity, id, action, detail) {
  await tx.auditLog.create({ data: { actorId: req.user.id, action, entity, entityId: id, detail } });
}
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
      prisma.product.findMany({ where: { organizationId: req.organizationId }, orderBy: { title: 'asc' } }),
    ]);
    res.json({ orders, total, products, limit, offset, transitions: transitions[kind] });
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
    const { isActive, title, category, description, priceMinor, currency } = req.body || {};
    const data = {};
    if (isActive !== undefined) { if (typeof isActive !== 'boolean') fail(400, 'Availability must be true or false.'); data.isActive = isActive; }
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
        product = await tx.product.findFirst({ where: { id: productId, organizationId: req.organizationId, isActive: true } });
        if (!product) fail(400, 'Choose an available product.');
        if (!validAmount(product.priceMinor * quantity)) fail(400, 'Order total is too large.');
      }
      const created = await tx.serviceOrder.create({ data: { organizationId: req.organizationId, kind, customerId,
        productId: product?.id, title: product?.title || title.trim(), sourceUrl: sourceUrl || null,
        quantity, currency: product?.currency || currency, amountMinor: product ? product.priceMinor * quantity : null, notes: notes?.trim() || null }, include: orderInclude });
      await audit(tx, req, 'ServiceOrder', created.id, 'SERVICE_ORDER_CREATE', `${kind}: ${created.title}`);
      return created;
    });
    res.status(201).json(result);
  } catch (e) { next(e); }
});
router.patch('/orders/:id', async (req, res, next) => {
  try {
    const { status, amountMinor, trackingId, notes } = req.body || {};
    if (amountMinor !== undefined && !validAmount(amountMinor)) fail(400, 'Enter a valid quote total.');
    if (notes !== undefined && (typeof notes !== 'string' || notes.length > 2000)) fail(400, 'Enter a valid note.');
    if (trackingId !== undefined && !validText(trackingId, 80)) fail(400, 'Enter a tracking number.');
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const existing = await tx.serviceOrder.findFirst({ where: { id: req.params.id, organizationId: req.organizationId } });
      if (!existing) fail(404, 'Order not found.');
      const data = {};
      if (status !== undefined) {
        if (!transitions[existing.kind][existing.status]?.includes(status)) fail(409, 'Invalid status change. Refresh this order.');
        data.status = status;
      }
      if (amountMinor !== undefined) {
        if (existing.kind !== 'BUY_FOR_ME' || !['REQUESTED', 'QUOTED'].includes(existing.status)) fail(409, 'Accepted quotes and marketplace price snapshots cannot be changed.');
        data.amountMinor = amountMinor;
      }
      if (status === 'QUOTED' && (data.amountMinor ?? existing.amountMinor) === null) fail(400, 'Record the total quote before marking it quoted.');
      if (trackingId !== undefined) {
        const parcel = await tx.parcel.findFirst({ where: { trackingId: trackingId.trim().toUpperCase(), customerId: existing.customerId, organizationId: req.organizationId } });
        if (!parcel) fail(400, 'Choose a parcel belonging to this customer and organization.');
        data.parcelId = parcel.id;
      }
      if (status === 'SHIPPED' && !(data.parcelId || existing.parcelId)) fail(400, 'Link the customer’s parcel before marking it shipped.');
      if (notes !== undefined) data.notes = notes.trim() || null;
      if (!Object.keys(data).length) fail(400, 'No changes provided.');
      const updated = await tx.serviceOrder.update({ where: { id: existing.id }, data, include: orderInclude });
      await audit(tx, req, 'ServiceOrder', existing.id, 'SERVICE_ORDER_UPDATE', JSON.stringify({ from: existing.status, ...data }));
      return updated;
    });
    res.json(result);
  } catch (e) { next(e); }
});
export default router;
