// Seller Studio — application, listing and order management for approved
// D2F Marketplace sellers. Sellers are ordinary customer accounts whose
// SellerProfile has been approved by an administrator with an agreed
// commission rate. Sellers see their own commercial trail; buyers never see
// commission details.

import { Router, raw } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { resolveOrganizationId } from '../tracking.js';
import { fail, warehouseLock } from '../warehouse.js';
import {
  audit,
  releaseStock,
  redactUnaccepted,
  sellerOrderSelect,
  validAmount,
  validOptionalText,
  validText,
  currencies,
} from '../shopfront.js';
import { createNotification } from '../notifications.js';

const router = Router();
router.use(authenticate, requireRole('CUSTOMER'));

const MAX_IMAGES_PER_PRODUCT = 6;
const MAX_IMAGE_BYTES = 4 * 1024 * 1024;
const IMAGE_CONTENT_TYPES = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

const profileSelect = {
  id: true,
  organizationId: true,
  status: true,
  displayName: true,
  businessType: true,
  businessName: true,
  headline: true,
  bio: true,
  category: true,
  phone: true,
  email: true,
  country: true,
  city: true,
  address: true,
  commissionBps: true,
  termsAcceptedAt: true,
  termsAccepted: true,
  verificationStatus: true,
  reviewNote: true,
  reviewedAt: true,
  createdAt: true,
  profilePictureName: true,
  bannerName: true,
};

const productSelect = {
  id: true,
  title: true,
  category: true,
  description: true,
  priceMinor: true,
  currency: true,
  isActive: true,
  fulfillment: true,
  stockCount: true,
  locationCity: true,
  locationCountry: true,
  featured: true,
  createdAt: true,
  updatedAt: true,
  images: { orderBy: { position: 'asc' }, select: { id: true, fileName: true, contentType: true, sizeBytes: true, position: true } },
  _count: { select: { orders: true } },
};

// Shop branding (profile photo + cover banner) rides the same bytes-in-DB
// policy as product photos, with human-readable file names for content types.
const brandingSelect = {
  ...profileSelect,
  profilePicture: true,
  profilePictureName: true,
  banner: true,
  bannerName: true,
};

const contentTypeFromName = (name) => {
  const ext = String(name || '').split('.').pop()?.toLowerCase();
  const entry = Object.entries(IMAGE_CONTENT_TYPES).find(([, value]) => value === ext);
  return entry ? entry[0] : 'image/jpeg';
};

async function myProfile(tx, userId) {
  return tx.sellerProfile.findUnique({ where: { userId }, select: profileSelect });
}

async function requireApproved(tx, userId) {
  const profile = await myProfile(tx, userId);
  if (!profile) fail(403, 'Apply to sell on the D2F Marketplace first.');
  if (profile.status === 'SUSPENDED') fail(403, 'Your seller account is suspended. Contact D2F support.');
  if (profile.status !== 'APPROVED') fail(403, 'Your seller application is still being reviewed.');
  return profile;
}

// ── Application ──────────────────────────────────────────────────────────────

router.post('/application', async (req, res, next) => {
  try {
    const { displayName, businessType = 'INDIVIDUAL', businessName, headline, bio, category, country, city, address, phone, terms } = req.body || {};
    if (!validText(displayName, 120) || !validText(category, 80) || !validText(country, 80) || !validText(phone, 40)) {
      fail(400, 'Enter a name, category, country and contact phone.');
    }
    if (!['INDIVIDUAL', 'BUSINESS'].includes(businessType)) fail(400, 'Choose individual or business.');
    if (businessType === 'BUSINESS' && !validText(businessName, 160)) fail(400, 'Enter your business name.');
    if (businessName != null && !validOptionalText(businessName, 160)) fail(400, 'Business name is too long.');
    if (!validOptionalText(headline, 160) || !validOptionalText(bio, 2000) || !validOptionalText(city, 120) || !validOptionalText(address, 300)) {
      fail(400, 'One of the fields is too long.');
    }
    if (terms !== true) fail(400, 'Accept the seller terms so D2F can agree your commission before your first sale.');

    const result = await prisma.$transaction(async (tx) => {
      const organizationId = await resolveOrganizationId(tx, req.user);
      const existing = await tx.sellerProfile.findUnique({ where: { userId: req.user.id } });
      if (existing?.status === 'APPROVED') fail(409, 'You are already an approved D2F seller.');
      if (existing?.status === 'SUSPENDED') fail(403, 'Your seller account is suspended. Contact D2F support.');
      const data = {
        organizationId,
        displayName: displayName.trim(),
        businessType,
        businessName: businessType === 'BUSINESS' ? businessName.trim() : null,
        headline: headline?.trim() || null,
        bio: bio?.trim() || null,
        category: category.trim(),
        phone: phone.trim(),
        email: req.user.email,
        country: country.trim(),
        city: city?.trim() || null,
        address: address?.trim() || null,
        termsAcceptedAt: new Date(),
        status: 'PENDING',
        reviewNote: null,
        reviewedAt: null,
        reviewedById: null,
      };
      const profile = existing
        ? await tx.sellerProfile.update({ where: { id: existing.id }, data, select: profileSelect })
        : await tx.sellerProfile.create({ data: { ...data, userId: req.user.id }, select: profileSelect });
      await audit(tx, req, 'SellerProfile', profile.id, existing ? 'SELLER_APPLICATION_UPDATE' : 'SELLER_APPLICATION_CREATE', data.displayName);
      return profile;
    });
    res.status(201).json(result);
  } catch (error) {
    next(error);
  }
});

router.get('/me', async (req, res, next) => {
  try {
    const profile = await prisma.sellerProfile.findUnique({ where: { userId: req.user.id }, select: profileSelect });
    if (!profile) return res.json({ profile: null });
    const [productCount, openOrders, verification] = await Promise.all([
      prisma.product.count({ where: { sellerId: profile.id } }),
      prisma.serviceOrder.count({ where: { sellerId: profile.id, status: { notIn: ['COMPLETED', 'CANCELLED'] } } }),
      prisma.sellerVerification.findUnique({ where: { sellerId: profile.id } }),
    ]);
    res.json({ profile, productCount, openOrders, verification });
  } catch (error) {
    next(error);
  }
});

// ── Seller terms acceptance ─────────────────────────────────────────────

router.post('/terms', async (req, res, next) => {
  try {
    const { accepted } = req.body || {};
    if (accepted !== true) fail(400, 'You must accept the marketplace terms.');
    const profile = await prisma.sellerProfile.update({
      where: { userId: req.user.id },
      data: { termsAccepted: true, termsAcceptedAt: new Date() },
      select: { id: true, termsAccepted: true, termsAcceptedAt: true, status: true },
    });
    await audit(prisma, req, 'SellerProfile', profile.id, 'SELLER_TERMS_ACCEPTED', 'accepted marketplace terms');
    res.json({ ok: true, termsAccepted: profile.termsAccepted, termsAcceptedAt: profile.termsAcceptedAt });
  } catch (error) {
    next(error);
  }
});

// ── Seller verification documents ───────────────────────────────────────

router.post('/verification', raw({ type: Object.keys(IMAGE_CONTENT_TYPES), limit: MAX_IMAGE_BYTES }), async (req, res, next) => {
  try {
    const { idDocumentType } = req.body || {};
    const extension = IMAGE_CONTENT_TYPES[req.headers['content-type']];
    if (!extension || !Buffer.isBuffer(req.body) || req.body.length < 16) {
      return res.status(415).json({ error: 'Attach a valid JPEG, PNG or WebP document.' });
    }
    const profile = await prisma.sellerProfile.findUnique({ where: { userId: req.user.id } });
    if (!profile) return res.status(404).json({ error: 'Seller profile not found.' });
    const existing = await prisma.sellerVerification.findUnique({ where: { sellerId: profile.id } });
    const data = {
      idDocumentType: idDocumentType || null,
      idDocumentName: req.query?.name || `verification-${Date.now()}.${extension}`,
      idDocumentBytes: req.body,
      status: 'PENDING',
    };
    const verification = existing
      ? await prisma.sellerVerification.update({ where: { sellerId: profile.id }, data })
      : await prisma.sellerVerification.create({ data: { ...data, sellerId: profile.id } });
    await audit(prisma, req, 'SellerVerification', verification.id, 'SELLER_VERIFICATION_SUBMITTED', `type=${idDocumentType}`);
    res.status(201).json({ ok: true, status: verification.status, id: verification.id });
  } catch (error) {
    next(error);
  }
});

router.get('/verification', async (req, res, next) => {
  try {
    const profile = await prisma.sellerProfile.findUnique({ where: { userId: req.user.id } });
    if (!profile) return res.status(404).json({ error: 'Seller profile not found.' });
    const verification = await prisma.sellerVerification.findUnique({ where: { sellerId: profile.id } });
    res.json({ verification });
  } catch (error) {
    next(error);
  }
});

router.get('/verification/document', async (req, res, next) => {
  try {
    const profile = await prisma.sellerProfile.findUnique({ where: { userId: req.user.id } });
    if (!profile) return res.status(404).json({ error: 'Seller profile not found.' });
    const verification = await prisma.sellerVerification.findUnique({ where: { sellerId: profile.id } });
    if (!verification?.idDocumentBytes) return res.status(404).json({ error: 'No document on file.' });
    res.set('Content-Type', 'image/jpeg');
    res.send(Buffer.from(verification.idDocumentBytes));
  } catch (error) {
    next(error);
  }
});

// ── Listings ─────────────────────────────────────────────────────────────────

router.get('/products', async (req, res, next) => {
  try {
    const profile = await myProfile(prisma, req.user.id);
    if (!profile) return res.json([]);
    const products = await prisma.product.findMany({
      where: { sellerId: profile.id },
      select: productSelect,
      orderBy: [{ updatedAt: 'desc' }],
      take: 200,
    });
    res.json(products);
  } catch (error) {
    next(error);
  }
});

router.post('/products', async (req, res, next) => {
  try {
    const { title, category, description, priceMinor, currency = 'USD', fulfillment = 'SELLER', stockCount, locationCity, locationCountry } = req.body || {};
    if (!validText(title) || !validText(category, 80)) fail(400, 'Enter a product title and category.');
    if (description != null && !validOptionalText(description, 2000)) fail(400, 'Description is too long.');
    if (!validAmount(priceMinor)) fail(400, 'Enter a valid price.');
    if (!currencies.includes(currency)) fail(400, 'Choose a supported currency.');
    if (!['SELLER', 'D2F'].includes(fulfillment)) fail(400, 'Choose who fulfils this listing.');
    if (stockCount != null && (!Number.isSafeInteger(stockCount) || stockCount < 0 || stockCount > 1000000)) {
      fail(400, 'Enter a valid stock count.');
    }
    if (!validOptionalText(locationCity, 120) || !validOptionalText(locationCountry, 120)) fail(400, 'Location is too long.');

    const result = await prisma.$transaction(async (tx) => {
      const profile = await requireApproved(tx, req.user.id);
      const created = await tx.product.create({
        data: {
          organizationId: profile.organizationId,
          sellerId: profile.id,
          title: title.trim(),
          category: category.trim(),
          description: description?.trim() || null,
          priceMinor,
          currency,
          fulfillment,
          stockCount: stockCount ?? null,
          locationCity: locationCity?.trim() || profile.city,
          locationCountry: locationCountry?.trim() || profile.country,
          isActive: true,
        },
        select: productSelect,
      });
      await audit(tx, req, 'Product', created.id, 'SELLER_PRODUCT_CREATE', created.title);
      return created;
    });
    res.status(201).json(result);
  } catch (error) {
    next(error);
  }
});

router.patch('/products/:id', async (req, res, next) => {
  try {
    const { title, category, description, priceMinor, currency, fulfillment, stockCount, isActive, locationCity, locationCountry } = req.body || {};
    const data = {};
    if (title !== undefined) { if (!validText(title)) fail(400, 'Enter a valid title.'); data.title = title.trim(); }
    if (category !== undefined) { if (!validText(category, 80)) fail(400, 'Enter a valid category.'); data.category = category.trim(); }
    if (description !== undefined) { if (!validOptionalText(description, 2000)) fail(400, 'Description is too long.'); data.description = description?.trim() || null; }
    if (priceMinor !== undefined) { if (!validAmount(priceMinor)) fail(400, 'Enter a valid price.'); data.priceMinor = priceMinor; }
    if (currency !== undefined) { if (!currencies.includes(currency)) fail(400, 'Choose a supported currency.'); data.currency = currency; }
    if (fulfillment !== undefined) { if (!['SELLER', 'D2F'].includes(fulfillment)) fail(400, 'Choose who fulfils this listing.'); data.fulfillment = fulfillment; }
    if (stockCount !== undefined) {
      if (stockCount === null) data.stockCount = null;
      else { if (!Number.isSafeInteger(stockCount) || stockCount < 0 || stockCount > 1000000) fail(400, 'Enter a valid stock count.'); data.stockCount = stockCount; }
    }
    if (isActive !== undefined) { if (typeof isActive !== 'boolean') fail(400, 'Availability must be true or false.'); data.isActive = isActive; }
    if (locationCity !== undefined) { if (!validOptionalText(locationCity, 120)) fail(400, 'City is too long.'); data.locationCity = locationCity?.trim() || null; }
    if (locationCountry !== undefined) { if (!validOptionalText(locationCountry, 120)) fail(400, 'Country is too long.'); data.locationCountry = locationCountry?.trim() || null; }
    if (!Object.keys(data).length) fail(400, 'No changes provided.');

    const result = await prisma.$transaction(async (tx) => {
      const profile = await requireApproved(tx, req.user.id);
      const existing = await tx.product.findFirst({ where: { id: req.params.id, sellerId: profile.id } });
      if (!existing) fail(404, 'Listing not found.');
      const updated = await tx.product.update({ where: { id: existing.id }, data, select: productSelect });
      await audit(tx, req, 'Product', existing.id, 'SELLER_PRODUCT_UPDATE', JSON.stringify(data));
      return updated;
    });
    res.json(result);
  } catch (error) {
    next(error);
  }
});

router.delete('/products/:id', async (req, res, next) => {
  try {
    const result = await prisma.$transaction(async (tx) => {
      const profile = await requireApproved(tx, req.user.id);
      const existing = await tx.product.findFirst({ where: { id: req.params.id, sellerId: profile.id }, select: { id: true, title: true, _count: { select: { orders: true } } } });
      if (!existing) fail(404, 'Listing not found.');
      if (existing._count.orders > 0) {
        // Orders keep their product reference; pause the listing instead of orphaning history.
        await tx.product.update({ where: { id: existing.id }, data: { isActive: false } });
        await audit(tx, req, 'Product', existing.id, 'SELLER_PRODUCT_PAUSE', existing.title);
        return { archived: true };
      }
      await tx.productImage.deleteMany({ where: { productId: existing.id } });
      await tx.product.delete({ where: { id: existing.id } });
      await audit(tx, req, 'Product', existing.id, 'SELLER_PRODUCT_DELETE', existing.title);
      return { archived: false };
    });
    res.json(result);
  } catch (error) {
    next(error);
  }
});

// ── Shop branding: profile photo + cover banner ──────────────────────────────

router.get('/me/profile-picture', async (req, res, next) => {
  try {
    const profile = await prisma.sellerProfile.findUnique({
      where: { userId: req.user.id },
      select: brandingSelect,
    });
    if (!profile?.profilePicture) return res.status(404).json({ error: 'No profile photo yet.' });
    res.set('Content-Type', contentTypeFromName(profile.profilePictureName));
    res.send(Buffer.from(profile.profilePicture));
  } catch (error) {
    next(error);
  }
});

router.get('/me/banner', async (req, res, next) => {
  try {
    const profile = await prisma.sellerProfile.findUnique({
      where: { userId: req.user.id },
      select: brandingSelect,
    });
    if (!profile?.banner) return res.status(404).json({ error: 'No banner yet.' });
    res.set('Content-Type', contentTypeFromName(profile.bannerName));
    res.send(Buffer.from(profile.banner));
  } catch (error) {
    next(error);
  }
});

const saveBrandingImage = async (req, res, next, slot) => {
  try {
    const profile = await requireApproved(prisma, req.user.id);
    const extension = IMAGE_CONTENT_TYPES[req.headers['content-type']];
    if (!extension || !Buffer.isBuffer(req.body) || req.body.length < 16) {
      return res.status(415).json({ error: 'Attach a JPEG, PNG or WebP photo for the shop branding.' });
    }
    const data = slot === 'profilePicture'
      ? { profilePicture: req.body, profilePictureName: validImageFileName(req.query?.name, extension) }
      : { banner: req.body, bannerName: validImageFileName(req.query?.name, extension) };
    const branding = await prisma.sellerProfile.update({
      where: { id: profile.id },
      data,
      select: brandingSelect,
    });
    await audit(prisma, req, 'SellerBranding', profile.id, slot === 'profilePicture' ? 'SELLER_PROFILE_PICTURE_UPLOAD' : 'SELLER_BANNER_UPLOAD', `slot=${slot}`);
    return res.json({
      ok: true,
      slot,
      profilePicture: branding.profilePicture ? { contentType: contentTypeFromName(branding.profilePictureName), sizeBytes: branding.profilePicture.length } : null,
      banner: branding.banner ? { contentType: contentTypeFromName(branding.bannerName), sizeBytes: branding.banner.length } : null,
    });
  } catch (error) {
    if (error?.type === 'entity.too.large' || error?.statusCode === 413) {
      return res.status(413).json({ error: 'That photo is larger than 4 MB. Please retry after compressing it.' });
    }
    next(error);
  }
};

router.post('/me/profile-picture', raw({ type: Object.keys(IMAGE_CONTENT_TYPES), limit: MAX_IMAGE_BYTES }), (req, res, next) => saveBrandingImage(req, res, next, 'profilePicture'));
router.post('/me/banner', raw({ type: Object.keys(IMAGE_CONTENT_TYPES), limit: MAX_IMAGE_BYTES }), (req, res, next) => saveBrandingImage(req, res, next, 'banner'));

// ── Product photos (bytes in PostgreSQL, same policy as goods photos) ────────

router.post('/products/:id/images', raw({ type: Object.keys(IMAGE_CONTENT_TYPES), limit: MAX_IMAGE_BYTES }), async (req, res, next) => {
  try {
    const extension = IMAGE_CONTENT_TYPES[req.headers['content-type']];
    if (!extension || !Buffer.isBuffer(req.body) || req.body.length < 16) {
      return res.status(415).json({ error: 'Attach a JPEG, PNG or WebP photo of the product.' });
    }
    const profile = await requireApproved(prisma, req.user.id);
    const product = await prisma.product.findFirst({ where: { id: req.params.id, sellerId: profile.id }, select: { id: true, _count: { select: { images: true } } } });
    if (!product) return res.status(404).json({ error: 'Listing not found.' });
    if (product._count.images >= MAX_IMAGES_PER_PRODUCT) {
      return res.status(409).json({ error: `A listing can hold at most ${MAX_IMAGES_PER_PRODUCT} photos.` });
    }
    const position = product._count.images;
    const fileName = validImageFileName(req.query.name?.toString(), extension);
    const image = await prisma.productImage.create({
      data: { productId: product.id, fileName, contentType: req.headers['content-type'], sizeBytes: req.body.length, bytes: req.body, position },
      select: { id: true, fileName: true, contentType: true, sizeBytes: true, position: true },
    });
    await prisma.auditLog.create({ data: { actorId: req.user.id, action: 'PRODUCT_IMAGE_UPLOAD', entity: 'Product', entityId: product.id, detail: `image=${image.fileName} bytes=${image.sizeBytes}` } });
    res.status(201).json(image);
  } catch (error) {
    if (error?.type === 'entity.too.large' || error?.statusCode === 413) {
      return res.status(413).json({ error: 'That photo is larger than 4 MB. Please retry after compressing it.' });
    }
    next(error);
  }
});

router.delete('/products/:id/images/:imageId', async (req, res, next) => {
  try {
    const profile = await requireApproved(prisma, req.user.id);
    const product = await prisma.product.findFirst({ where: { id: req.params.id, sellerId: profile.id }, select: { id: true } });
    if (!product) return res.status(404).json({ error: 'Listing not found.' });
    const removed = await prisma.productImage.deleteMany({ where: { id: req.params.imageId, productId: product.id } });
    if (removed.count !== 1) return res.status(404).json({ error: 'Photo not found.' });
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

// ── Seller orders ────────────────────────────────────────────────────────────

router.get('/orders', async (req, res, next) => {
  try {
    const profile = await myProfile(prisma, req.user.id);
    if (!profile) return res.json([]);
    const status = typeof req.query.status === 'string' ? req.query.status.toUpperCase() : null;
    const allowed = ['REQUESTED', 'ACCEPTED', 'PROCESSING', 'SHIPPED', 'COMPLETED', 'CANCELLED'];
    const orders = await prisma.serviceOrder.findMany({
      where: { sellerId: profile.id, kind: 'MARKETPLACE', ...(status && allowed.includes(status) ? { status } : {}) },
      select: sellerOrderSelect,
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    res.json(redactUnaccepted(orders));
  } catch (error) {
    next(error);
  }
});

router.post('/orders/:id/accept', (req, res, next) => advance(req, res, next, { from: ['REQUESTED'], to: 'ACCEPTED', action: 'MARKETPLACE_ORDER_ACCEPT' }));
router.post('/orders/:id/decline', (req, res, next) => advance(req, res, next, { from: ['REQUESTED'], to: 'CANCELLED', action: 'MARKETPLACE_ORDER_DECLINE', requireNote: true, noteField: 'reason' }));
router.post('/orders/:id/cancel', (req, res, next) => advance(req, res, next, { from: ['ACCEPTED', 'PROCESSING'], to: 'CANCELLED', action: 'MARKETPLACE_ORDER_CANCEL', requireNote: true, noteField: 'reason' }));
router.post('/orders/:id/advance', (req, res, next) => advance(req, res, next, { from: ['ACCEPTED'], to: 'PROCESSING', action: 'MARKETPLACE_ORDER_PROCESSING', optionalField: 'trackingRef' }));
router.post('/orders/:id/ship', (req, res, next) => advance(req, res, next, { from: ['PROCESSING'], to: 'SHIPPED', action: 'MARKETPLACE_ORDER_SHIP', optionalField: 'trackingRef' }));
router.post('/orders/:id/complete', (req, res, next) => advance(req, res, next, { from: ['SHIPPED'], to: 'COMPLETED', action: 'MARKETPLACE_ORDER_COMPLETE' }));

async function advance(req, res, next, { from, to, action, requireNote = false, noteField = 'note', optionalField }) {
  try {
    const note = typeof req.body?.[noteField] === 'string' ? req.body[noteField].trim() : '';
    if (requireNote && !validText(note, 500)) fail(400, 'Tell the buyer why this order cannot proceed.');
    const trackingRef = typeof req.body?.trackingRef === 'string' ? req.body.trackingRef.trim() : '';
    if (optionalField === 'trackingRef' && trackingRef && trackingRef.length > 120) fail(400, 'Tracking reference is too long.');
    const result = await prisma.$transaction(async (tx) => {
      const profile = await requireApproved(tx, req.user.id);
      const order = await tx.serviceOrder.findFirst({ where: { id: req.params.id, sellerId: profile.id, kind: 'MARKETPLACE' }, select: { ...sellerOrderSelect, customer: { select: { userId: true } } } });
      if (!order) fail(404, 'Order not found.');
      if (!from.includes(order.status)) fail(409, 'This order already moved on. Refresh and try again.');
      const data = { status: to };
      if (to === 'CANCELLED') data.notes = [order.notes, note ? `Seller: ${note}` : null].filter(Boolean).join('\n') || null;
      if (trackingRef) data.trackingRef = trackingRef;
      const updated = await tx.serviceOrder.update({ where: { id: order.id }, data, select: sellerOrderSelect });
      if (to === 'CANCELLED') await releaseStock(tx, order.productId, order.quantity);
      await audit(tx, req, 'ServiceOrder', order.id, action, trackingRef ? `trackingRef=${trackingRef}` : note || `${order.status} → ${to}`);
      const buyerUserId = order.customer?.userId ?? null;
      if (to === 'ACCEPTED' && buyerUserId) {
        await createNotification({
          userId: buyerUserId,
          type: 'ORDER_ACCEPTED',
          title: 'Your order was accepted',
          body: `${order.title} ×${order.quantity} is being prepared. D2F or the seller will coordinate the next step with you.`,
        });
      }
      if (to === 'SHIPPED' && buyerUserId) {
        await createNotification({
          userId: buyerUserId,
          type: 'ORDER_SHIPPED',
          title: 'Your order has shipped',
          body: order.trackingRef ? `Carrier reference ${order.trackingRef}.` : 'The seller shipped your order.',
        });
      }
      if (to === 'COMPLETED') {
        if (buyerUserId) {
          await createNotification({
            userId: buyerUserId,
            type: 'ORDER_COMPLETED',
            title: 'Order completed',
            body: 'Your marketplace order is complete. D2F will follow up on the agreed settlement.',
          });
        }
      }
      return updated;
    });
    res.json(redactUnaccepted([result])[0]);
  } catch (error) {
    next(error);
  }
}

// Buyer contact details are withheld before acceptance; after ACCEPTED the
// seller needs them to arrange delivery or shipping. redactUnaccepted()
// applies the rule on every seller-facing response.
function validImageFileName(value, extension) {
  const base = typeof value === 'string' ? value.trim() : '';
  const safe = base.replace(/[^\w.\- ]+/g, '_').replace(/^\.+/, '').slice(0, 100);
  return safe || `product.${extension}`;
}

export default router;
