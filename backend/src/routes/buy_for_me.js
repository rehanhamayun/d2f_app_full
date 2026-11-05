// Buy For Me — customer-facing purchase requests. The buyer describes the
// item and target budget; an administrator quotes, the buyer accepts, and
// D2F purchases and ships it. Payment is coordinated offline — the app
// tracks the request and never collects card details.

import { Router } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
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
};

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
    res.json(requests);
  } catch (error) {
    next(error);
  }
});

router.post('/requests', async (req, res, next) => {
  try {
    const { title, sourceUrl, quantity = 1, budgetMinor, currency = 'USD', notes } = req.body || {};
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

    const result = await prisma.$transaction(async (tx) => {
      const customer = await upsertCustomer(tx, req.user);
      await warehouseLock(tx, customer.organizationId);
      const created = await tx.serviceOrder.create({
        data: {
          organizationId: customer.organizationId,
          kind: 'BUY_FOR_ME',
          customerId: customer.id,
          title: title.trim(),
          sourceUrl: sourceUrl?.trim() || null,
          quantity,
          budgetMinor: budgetMinor ?? null,
          currency,
          notes: notes?.trim() || null,
          status: 'REQUESTED',
          source: 'APP',
        },
        select: requestSelect,
      });
      await audit(tx, req, 'ServiceOrder', created.id, 'BUY_FOR_ME_REQUEST', created.title);
      return created;
    });
    res.status(201).json(result);
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
    res.json(result);
  } catch (error) {
    next(error);
  }
});

export default router;
