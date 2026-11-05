// Payments — tracks all payments for Buy For Me and Ship For Me.
// Supports card, bank transfer, mobile money, and manual verification.
import { Router } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { fail } from '../warehouse.js';
import { audit, validAmount, validOptionalText, validText } from '../shopfront.js';
import { createNotification } from '../notifications.js';

const router = Router();
router.use(authenticate);

const paymentSelect = {
  id: true,
  buyForMeRequestId: true,
  shipForMeRequestId: true,
  customerId: true,
  organizationId: true,
  amountMinor: true,
  currency: true,
  paymentMethod: true,
  paymentProvider: true,
  providerReference: true,
  status: true,
  purpose: true,
  verificationNotes: true,
  verifiedBy: true,
  verifiedAt: true,
  verificationImage: true,
  createdAt: true,
  updatedAt: true,
  completedAt: true,
};

// ── Get my payments ─────────────────────────────────────────────────────

router.get('/', async (req, res, next) => {
  try {
    const customer = await prisma.customer.findUnique({
      where: { userId: req.user.id },
      select: { id: true },
    });
    if (!customer) return res.json([]);
    const payments = await prisma.payment.findMany({
      where: { customerId: customer.id },
      select: paymentSelect,
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
    res.json(payments);
  } catch (error) {
    next(error);
  }
});

// ── Create a payment (customer initiates) ───────────────────────────────

router.post('/', async (req, res, next) => {
  try {
    const {
      buyForMeRequestId, shipForMeRequestId,
      amountMinor, currency = 'USD', paymentMethod,
      paymentProvider, purpose = 'QUOTE_PAYMENT',
      verificationImage,
    } = req.body || {};

    if (!amountMinor || !validAmount(amountMinor) || amountMinor <= 0) {
      fail(400, 'Enter a valid payment amount.');
    }
    if (!['CARD', 'BANK_TRANSFER', 'MOBILE_MONEY', 'MANUAL', 'WALLET'].includes(paymentMethod)) {
      fail(400, 'Choose a valid payment method.');
    }
    if (!currencies.includes(currency)) fail(400, 'Choose a supported currency.');

    const customer = await prisma.customer.findUnique({
      where: { userId: req.user.id },
      select: { id: true, organizationId: true },
    });
    if (!customer) fail(404, 'Customer profile not found.');

    // Verify the request belongs to this customer
    if (buyForMeRequestId) {
      const bfm = await prisma.buyForMeRequest.findUnique({
        where: { id: buyForMeRequestId },
        select: { customerId: true, status: true },
      });
      if (!bfm || bfm.customerId !== customer.id) fail(404, 'Request not found.');
    }
    if (shipForMeRequestId) {
      const sfm = await prisma.shipForMeRequest.findUnique({
        where: { id: shipForMeRequestId },
        select: { customerId: true, status: true },
      });
      if (!sfm || sfm.customerId !== customer.id) fail(404, 'Request not found.');
    }

    const result = await prisma.$transaction(async (tx) => {
      const created = await tx.payment.create({
        data: {
          customerId: customer.id,
          organizationId: customer.organizationId,
          buyForMeRequestId: buyForMeRequestId || null,
          shipForMeRequestId: shipForMeRequestId || null,
          amountMinor,
          currency,
          paymentMethod,
          paymentProvider: paymentProvider || null,
          purpose,
          verificationImage: verificationImage || null,
          status: paymentMethod === 'MANUAL' ? 'PENDING' : 'PENDING',
        },
        select: paymentSelect,
      });
      await audit(tx, req, 'Payment', created.id, 'PAYMENT_CREATE', `${paymentMethod} ${amountMinor} ${currency}`);
      return created;
    });
    res.status(201).json(result);
  } catch (error) {
    next(error);
  }
});

// ── Verify a payment (admin) ────────────────────────────────────────────

router.post('/:id/verify', requireRole('ADMIN', 'STAFF'), async (req, res, next) => {
  try {
    const { status, notes } = req.body || {};
    if (!['COMPLETED', 'FAILED'].includes(status)) {
      fail(400, 'Choose completed or failed.');
    }
    const result = await prisma.$transaction(async (tx) => {
      const existing = await tx.payment.findUnique({ where: { id: req.params.id } });
      if (!existing) fail(404, 'Payment not found.');
      if (existing.status !== 'PENDING') fail(409, 'Payment already processed.');
      const updated = await tx.payment.update({
        where: { id: existing.id },
        data: {
          status,
          verificationNotes: notes?.trim() || null,
          verifiedBy: req.user.id,
          verifiedAt: new Date(),
          ...(status === 'COMPLETED' && { completedAt: new Date() }),
        },
        select: paymentSelect,
      });
      await audit(tx, req, 'Payment', existing.id, `PAYMENT_${status}`, `verified by ${req.user.fullName}`);
      // Notify customer
      await createNotification({
        userId: existing.customerId,
        type: 'PAYMENT_VERIFIED',
        title: status === 'COMPLETED' ? 'Payment confirmed' : 'Payment failed',
        body: status === 'COMPLETED'
          ? `Your payment of ${existing.amountMinor} ${existing.currency} has been confirmed.`
          : `Your payment could not be verified. ${notes || ''}`,
      });
      return updated;
    });
    res.json(result);
  } catch (error) {
    next(error);
  }
});

// ── Refund a payment (admin) ────────────────────────────────────────────

router.post('/:id/refund', requireRole('ADMIN'), async (req, res, next) => {
  try {
    const { amountMinor, reason } = req.body || {};
    if (!amountMinor || !validAmount(amountMinor) || amountMinor <= 0) {
      fail(400, 'Enter a valid refund amount.');
    }
    const result = await prisma.$transaction(async (tx) => {
      const existing = await tx.payment.findUnique({ where: { id: req.params.id } });
      if (!existing) fail(404, 'Payment not found.');
      if (existing.status !== 'COMPLETED') fail(409, 'Only completed payments can be refunded.');
      if (amountMinor > existing.amountMinor) fail(400, 'Refund exceeds payment amount.');
      const updated = await tx.payment.update({
        where: { id: existing.id },
        data: {
          status: amountMinor === existing.amountMinor ? 'REFUNDED' : 'PARTIAL',
          verificationNotes: reason?.trim() || null,
        },
        select: paymentSelect,
      });
      await audit(tx, req, 'Payment', existing.id, 'PAYMENT_REFUND', `refunded ${amountMinor} ${existing.currency}`);
      await createNotification({
        userId: existing.customerId,
        type: 'PAYMENT_REFUNDED',
        title: 'Payment refunded',
        body: `A refund of ${amountMinor} ${existing.currency} has been issued. ${reason || ''}`,
      });
      return updated;
    });
    res.json(result);
  } catch (error) {
    next(error);
  }
});

export default router;
