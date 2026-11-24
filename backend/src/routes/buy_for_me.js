// Buy For Me — customer-facing purchase requests. The buyer describes the
// item and target budget; an administrator quotes, the buyer accepts, and
// D2F purchases and ships it. Payment is coordinated offline — the app
// tracks the request and never collects card details.

import { Router, raw } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { defaultRetailers } from '../retailers.js';
import { resolveOrganizationId } from '../tracking.js';
import { fail, warehouseLock } from '../warehouse.js';
import {
  audit,
  currencies,
  customerOrderSelect,
  upsertCustomer,
  validAmount,
  validOptionalText,
  validText,
} from '../shopfront.js';

const router = Router();
router.use(authenticate, requireRole('CUSTOMER'));

const requestSelect = {
  ...customerOrderSelect,
  amountMinor: true, // null until quoted — the customer only sees it here
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
const paymentInstructions = () => process.env.D2F_ZELLE_ACCOUNT
  ? `Zelle: ${process.env.D2F_ZELLE_ACCOUNT}`
  : 'Please contact D2F to confirm payment instructions before paying.';
const customerOrder = order => ({
  ...order,
  paymentInstructions: order.status === 'ACCEPTED' ? paymentInstructions() : null,
});

router.get('/retailers', async (req, res, next) => {
  try {
    const customer = await prisma.customer.findUnique({ where: { userId: req.user.id }, select: { organizationId: true } });
    const id = await resolveOrganizationId(prisma, { ...req.user, organizationId: req.user.organizationId || customer?.organizationId });
    const { retailerLinks } = await prisma.organization.findUniqueOrThrow({ where: { id }, select: { retailerLinks: true } });
    res.json((retailerLinks ?? defaultRetailers).filter(store => store.enabled));
  } catch (error) { next(error); }
});

router.get('/requests', async (req, res, next) => {
  try {
    const customer = await prisma.customer.findUnique({ where: { userId: req.user.id }, select: { id: true } });
    if (!customer) return res.json([]);
    const requests = await prisma.serviceOrder.findMany({
      where: { customerId: customer.id, kind: 'BUY_FOR_ME', source: 'APP' },
      select: requestSelect,
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
    res.json(requests.map(customerOrder));
  } catch (error) {
    next(error);
  }
});

router.post('/requests', async (req, res, next) => {
  try {
    const {
      title, sourceUrl, quantity = 1, budgetMinor, currency = 'USD', notes, clientRequestId,
      deliveryAddress, deliveryCity, deliveryStateProvince, deliveryPostalCode, deliveryCountry,
    } = req.body || {};
    if (clientRequestId != null && !validText(clientRequestId, 120)) fail(400, 'Enter a valid request identifier.');
    if (!validText(title)) fail(400, 'Describe the item you want.');
    if (sourceUrl != null && typeof sourceUrl !== 'string') fail(400, 'Enter a valid product link.');
    if (sourceUrl && sourceUrl.trim()) {
      try {
        if (!['http:', 'https:'].includes(new URL(sourceUrl.trim()).protocol) || sourceUrl.length > 2000) throw new Error();
      } catch {
        fail(400, 'Enter a valid HTTP or HTTPS product link.');
      }
    }
    if (!Number.isSafeInteger(quantity) || quantity < 1 || quantity > 1000) fail(400, 'Choose a valid quantity.');
    if (budgetMinor != null && !validAmount(budgetMinor)) fail(400, 'Enter a valid budget.');
    if (!currencies.includes(currency)) fail(400, 'Choose a supported currency.');
    if (!validOptionalText(notes, 2000)) fail(400, 'Notes are too long.');
    if (!validText(deliveryAddress, 500)) fail(400, 'Enter a complete delivery address.');
    if (!validText(deliveryCity, 100)) fail(400, 'Enter a delivery city.');
    if (!validOptionalText(deliveryStateProvince, 100)) fail(400, 'Enter a valid state or region.');
    if (!validText(deliveryPostalCode, 20)) fail(400, 'Enter a ZIP or postal code.');
    if (!validText(deliveryCountry, 100)) fail(400, 'Enter a delivery country.');

    let isNewRequest = true;
    const result = await prisma.$transaction(async (tx) => {
      const customer = await upsertCustomer(tx, req.user);
      await warehouseLock(tx, customer.organizationId);
      if (clientRequestId) {
        const previous = await tx.serviceOrder.findUnique({
          where: { organizationId_clientRequestId: { organizationId: customer.organizationId, clientRequestId } },
          select: { ...requestSelect, customerId: true },
        });
        if (previous) {
          if (previous.customerId !== customer.id || previous.kind !== 'BUY_FOR_ME' || previous.source !== 'APP') fail(409, 'This request identifier has already been used.');
          const expected = { title: title.trim(), sourceUrl: sourceUrl?.trim() || null, quantity, budgetMinor: budgetMinor ?? null, currency, notes: notes?.trim() || null,
            deliveryAddress: deliveryAddress.trim(), deliveryCity: deliveryCity.trim(), deliveryStateProvince: deliveryStateProvince?.trim() || null,
            deliveryPostalCode: deliveryPostalCode.trim(), deliveryCountry: deliveryCountry.trim() };
          if (Object.entries(expected).some(([key, value]) => previous[key] !== value)) fail(409, 'This request was already submitted. Open your purchase requests to review it before starting another.');
          isNewRequest = false;
          const { customerId: _privateCustomerId, ...safe } = previous;
          return safe;
        }
      }

      const created = await tx.serviceOrder.create({
        data: {
          organizationId: customer.organizationId,
          kind: 'BUY_FOR_ME',
          clientRequestId: clientRequestId || null,
          customerId: customer.id,
          title: title.trim(),
          sourceUrl: sourceUrl?.trim() || null,
          quantity,
          budgetMinor: budgetMinor ?? null,
          currency,
          notes: notes?.trim() || null,
          deliveryAddress: deliveryAddress.trim(),
          deliveryCity: deliveryCity.trim(),
          deliveryStateProvince: deliveryStateProvince?.trim() || null,
          deliveryPostalCode: deliveryPostalCode.trim(),
          deliveryCountry: deliveryCountry.trim(),
          status: 'REQUESTED',
          source: 'APP',
        },
        select: requestSelect,
      });
      await audit(tx, req, 'ServiceOrder', created.id, 'BUY_FOR_ME_REQUEST', created.title);
      return created;
    });
    res.status(isNewRequest ? 201 : 200).json(customerOrder(result));
  } catch (error) {
    next(error);
  }
});

router.post(
  '/requests/:id/payment-submissions',
  raw({ type: ['image/jpeg', 'image/png', 'image/webp'], limit: '4mb' }),
  async (req, res, next) => {
    try {
      const bytes = req.body;
      const mime = req.headers['content-type']?.split(';')[0];
      const valid = Buffer.isBuffer(bytes) && bytes.length > 12 && (
        (mime === 'image/jpeg' && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) ||
        (mime === 'image/png' && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) ||
        (mime === 'image/webp' && bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP')
      );
      if (!valid) fail(400, 'Upload a valid JPEG, PNG or WebP payment screenshot (up to 4 MB).');
      const transactionId = req.query.transactionId;
      if (!validText(transactionId, 120)) fail(400, 'Enter the payment transaction ID.');
      const result = await prisma.$transaction(async tx => {
        const customer = await tx.customer.findUnique({
          where: { userId: req.user.id },
          select: { id: true, organizationId: true },
        });
        if (!customer) fail(404, 'Request not found.');
        if (customer.organizationId) await warehouseLock(tx, customer.organizationId);
        const order = await tx.serviceOrder.findFirst({
          where: { id: req.params.id, customerId: customer.id, kind: 'BUY_FOR_ME', source: 'APP' },
        });
        if (!order) fail(404, 'Request not found.');
        if (order.status !== 'ACCEPTED' || order.paymentStatus === 'VERIFIED') {
          fail(409, 'Accept the quote before submitting payment evidence.');
        }
        const pending = await tx.serviceOrderPaymentSubmission.count({
          where: { serviceOrderId: order.id, status: 'PENDING' },
        });
        if (pending) fail(409, 'Your payment evidence is already awaiting review.');
        const submission = await tx.serviceOrderPaymentSubmission.create({
          data: {
            serviceOrderId: order.id,
            userId: req.user.id,
            method: 'ZELLE',
            transactionId: transactionId.trim(),
            fileName: 'payment-proof',
            contentType: mime,
            bytes,
          },
          select: { id: true, method: true, transactionId: true, status: true, createdAt: true },
        });
        await tx.serviceOrder.update({
          where: { id: order.id },
          data: { paymentStatus: 'PENDING', paymentTransactionId: transactionId.trim() },
        });
        await audit(tx, req, 'ServiceOrder', order.id, 'BUY_FOR_ME_PAYMENT_SUBMITTED', transactionId.trim());
        return submission;
      });
      res.status(201).json(result);
    } catch (error) {
      next(error);
    }
  },
);

router.get('/requests/:id/payment-submissions/:submissionId/image', async (req, res, next) => {
  try {
    const customer = await prisma.customer.findUnique({ where: { userId: req.user.id }, select: { id: true } });
    const order = customer && await prisma.serviceOrder.findFirst({
      where: { id: req.params.id, customerId: customer.id, kind: 'BUY_FOR_ME', source: 'APP' },
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
  } catch (error) {
    next(error);
  }
});

router.get('/requests/:id/updates/:updateId/image', async (req, res, next) => {
  try {
    const customer = await prisma.customer.findUnique({ where: { userId: req.user.id }, select: { id: true } });
    const order = customer && await prisma.serviceOrder.findFirst({
      where: { id: req.params.id, customerId: customer.id, kind: 'BUY_FOR_ME', source: 'APP' },
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
  } catch (error) {
    next(error);
  }
});

// Customer decisions on a quoted request.
const decisions = {
  accept: { from: ['QUOTED'], to: 'ACCEPTED', action: 'BUY_FOR_ME_ACCEPT', detail: 'customer accepted the quote' },
  decline: { from: ['QUOTED'], to: 'CANCELLED', action: 'BUY_FOR_ME_DECLINE', detail: 'customer declined the quote' },
  cancel: { from: ['REQUESTED', 'QUOTED'], to: 'CANCELLED', action: 'BUY_FOR_ME_CANCEL', detail: 'cancelled by customer' },
};

router.post('/requests/:id/:decision', async (req, res, next) => {
  try {
    const rule = decisions[req.params.decision];
    if (!rule) fail(404, 'Not found.');
    const result = await prisma.$transaction(async (tx) => {
      const customer = await tx.customer.findUnique({ where: { userId: req.user.id }, select: { id: true, organizationId: true } });
      if (!customer) fail(404, 'Request not found.');
      if (customer.organizationId) await warehouseLock(tx, customer.organizationId);
      const existing = await tx.serviceOrder.findFirst({
        where: { id: req.params.id, customerId: customer.id, kind: 'BUY_FOR_ME', source: 'APP' },
      });
      if (!existing) fail(404, 'Request not found.');
      if (req.params.decision === 'accept') {
        const { expectedAmountMinor, expectedCurrency, expectedUpdatedAt } = req.body || {};
        if (expectedAmountMinor !== undefined && (!validAmount(expectedAmountMinor) || expectedAmountMinor !== existing.amountMinor)) fail(409, 'Your quote changed. Review the latest product and shipping costs before accepting.');
        if (expectedUpdatedAt != null && Date.parse(expectedUpdatedAt) !== existing.updatedAt.getTime()) fail(409, 'Your quote changed. Review the latest breakdown before accepting.');
        if ((existing.pickupFeeMinor || existing.handlingFeeMinor) && expectedAmountMinor === undefined) fail(409, 'Open the latest D2F app to review and accept the complete quote.');
        if (expectedCurrency !== undefined && expectedCurrency !== existing.currency) fail(409, 'Your quote currency changed. Review the latest quote before accepting.');
      }
      if (!rule.from.includes(existing.status)) {
        fail(409, existing.status === 'QUOTED' || existing.status === 'REQUESTED'
          ? 'This request already moved on. Refresh and try again.'
          : 'This request is already in progress — contact D2F to make changes.');
      }
      const updated = await tx.serviceOrder.update({
        where: { id: existing.id },
        data: { status: rule.to },
        select: requestSelect,
      });
      await audit(tx, req, 'ServiceOrder', existing.id, rule.action, rule.detail);
      return updated;
    });
    res.json(customerOrder(result));
  } catch (error) {
    next(error);
  }
});

export default router;
