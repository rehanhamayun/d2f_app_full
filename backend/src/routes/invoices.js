import { Router } from 'express';
import jwt from 'jsonwebtoken';
import { createHash } from 'node:crypto';
import { JWT_SECRET } from '../config.js';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { currencies, validAmount, validText } from '../shopfront.js';
import { resolveOrganizationId } from '../tracking.js';
import { fail, warehouseLock } from '../warehouse.js';

const router = Router();
const invoiceTypes = ['shipment', 'connect', 'marketplace', 'buy-for-me', 'ship-for-me'];
const printable = new Set(['SEA', 'AIR_CARGO', 'ROAD']);
const parties = {
  customer: { select: { displayName: true } },
  organization: { select: { name: true } },
};
const wrap = handler => async (req, res, next) => {
  try { await handler(req, res); } catch (error) { next(error); }
};
const line = (label, amountMinor) => ({ label, amountMinor });
const statuses = {
  VERIFIED: 'Paid', PAID: 'Paid', UNPAID: 'Awaiting payment',
  NOT_SUBMITTED: 'Awaiting payment', PENDING: 'Payment under review',
  PARTIAL: 'Partially paid', REJECTED: 'Payment needs correction', REFUNDED: 'Refunded', PARTIALLY_REFUNDED: 'Partially refunded',
};

async function invoice(type, id, scope) {
  const where = { id, ...scope };
  const base = (row, service, number, totalMinor, issuedAt, lines, currency, status) => ({
    service, number, totalMinor, issuedAt: new Date(issuedAt).toISOString(),
    currency, status: statuses[status] || 'Payment status unavailable',
    issuer: row.organization.name, buyer: row.customer.displayName,
    reference: id, lines: lines.filter(item => Number.isSafeInteger(item.amountMinor) && item.amountMinor >= 0),
  });
  switch (type) {
    case 'shipment': {
      const p = await prisma.parcel.findFirst({ where, include: parties });
      if (!p?.shipmentInvoice) return null;
      const d = p.shipmentInvoice;
      return {
        ...base(p, d.service || p.serviceType.replaceAll('_', ' '), d.number, d.amountMinor, d.issuedAt,
          [line('Shipping charge', d.amountMinor)], d.currency, d.paidAt ? 'PAID' : 'UNPAID'),
        issuer: d.issuer || p.organization.name, buyer: d.buyer || p.customer.displayName,
        reference: p.trackingId, route: d.route || `${p.origin} → ${p.destination}`,
      };
    }
    case 'connect': {
      const { customer, ...bookingScope } = scope;
      const b = await prisma.connectBooking.findFirst({
        where: { id, ...bookingScope, ...(customer && { parcel: { customer } }) },
        include: { payment: true, organization: parties.organization, parcel: { include: { customer: parties.customer } } },
      });
      if (!b?.quoteAcceptedAt || b.internationalFeeMinor == null || b.domesticCostMinor == null) return null;
      return {
        ...base({ ...b, customer: b.parcel.customer }, 'D2F Connect', `D2F-CN-${b.parcel.trackingId}`,
          b.internationalFeeMinor + b.domesticCostMinor, b.quoteAcceptedAt,
          [line('International shipping', b.internationalFeeMinor), line('Domestic carrier cost', b.domesticCostMinor)],
          b.currency, b.payment ? 'PAID' : 'UNPAID'),
        reference: b.parcel.trackingId, route: `${b.parcel.origin} → ${b.parcel.destination}`,
      };
    }
    case 'marketplace': {
      const o = await prisma.serviceOrder.findFirst({ where: { ...where, kind: 'MARKETPLACE' }, include: { ...parties, marketplaceIssues: true } });
      const d = o?.marketplaceInvoice;
      if (!d) return null;
      const refunds = o.marketplaceIssues.filter(row => row.type === 'REFUND' && row.status === 'RESOLVED')
        .reduce((sum, row) => sum + (row.amountMinor || 0), 0);
      return {
        ...base(o, 'Marketplace', d.number, d.totalMinor, d.issuedAt,
          [line(`${d.item} × ${d.quantity}`, d.subtotalMinor)], d.currency, o.paymentStatus),
        issuer: d.issuer, issuerLocation: d.issuerLocation, buyer: d.buyer,
        ...(refunds > 0 && { refundsMinor: refunds }),
      };
    }
    case 'buy-for-me': {
      const o = await prisma.serviceOrder.findFirst({ where: { ...where, kind: 'BUY_FOR_ME' }, include: {
        ...parties, updates: { where: { status: 'ACCEPTED' }, orderBy: { createdAt: 'asc' }, take: 1 },
      } });
      if (!o || o.amountMinor == null || !['ACCEPTED', 'PAYMENT_CONFIRMED', 'PURCHASED', 'RECEIVED', 'SHIPPED', 'COMPLETED'].includes(o.status)) return null;
      return base(o, 'Buy For Me', `D2F-BF-${id.toUpperCase()}`, o.amountMinor, o.updates[0]?.createdAt ?? o.createdAt,
        [line(`${o.title} × ${o.quantity}`, o.productCostMinor), line('International shipping', o.shippingCostMinor),
          line('Door pickup', o.pickupFeeMinor || null), line('Handling / preparation', o.handlingFeeMinor || null)],
        o.currency, o.paymentStatus);
    }
    case 'ship-for-me': {
      const o = await prisma.shipForMeRequest.findFirst({ where, include: { ...parties, payments: { where: { currency: 'USD', status: { in: ['COMPLETED', 'REFUNDED', 'PARTIAL'] } }, select: { status: true } } } });
      if (!o || o.totalQuoteMinor == null || !['ACCEPTED', 'PAID', 'SHIPPED', 'COMPLETED'].includes(o.status)) return null;
      // The existing Ship For Me quote is denominated in USD. The declared
      // currency describes the retailer goods for customs, independently.
      const status = o.payments.some(row => row.status === 'COMPLETED') ? o.paymentStatus
        : o.payments.some(row => row.status === 'PARTIAL') ? 'PARTIALLY_REFUNDED'
          : o.payments.some(row => row.status === 'REFUNDED') ? 'REFUNDED' : o.paymentStatus;
      return base(o, 'Ship For Me', `D2F-SF-${id.toUpperCase()}`, o.totalQuoteMinor, o.quoteAcceptedAt ?? o.paidAt ?? o.acceptedAt ?? o.createdAt,
        [line('Shipping', o.shippingFeeMinor), line('Insurance', o.insuranceFeeMinor), line('Handling', o.handlingFeeMinor)],
        'USD', status);
    }
    default:
      return null;
  }
}

async function authenticatedInvoice(req) {
  const { type, id } = req.params;
  if (!invoiceTypes.includes(type) || !validText(id, 160)) fail(404, 'Invoice unavailable.');
  const scope = req.user.role === 'CUSTOMER'
    ? { customer: { userId: req.user.id } }
    : { organizationId: await resolveOrganizationId(prisma, req.user) };
  const result = await invoice(type, id, scope);
  if (!result) fail(404, 'An invoice is available after D2F records the agreed charges.');
  return result;
}
const authorized = [authenticate, requireRole('CUSTOMER', 'STAFF', 'ADMIN')];
const escape = value => String(value ?? '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]);
router.get('/view/:share', wrap(async (req, res) => {
  res.set({
    'Cache-Control': 'private, no-store',
    'Referrer-Policy': 'no-referrer',
    'X-Robots-Tag': 'noindex, nofollow, noarchive',
    'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'",
    'X-Content-Type-Options': 'nosniff',
  });
  let token;
  try { token = jwt.verify(req.params.share, JWT_SECRET, { algorithms: ['HS256'] }); }
  catch { return res.status(404).type('text').send('This invoice link is invalid or expired.'); }
  if (token.purpose !== 'invoice-share' || !invoiceTypes.includes(token.type) || !validText(token.invoiceId, 160)) {
    return res.status(404).type('text').send('This invoice link is invalid or expired.');
  }
  const d = await invoice(token.type, token.invoiceId, {});
  if (!d) return res.status(404).type('text').send('This invoice is unavailable.');
  const money = value => new Intl.NumberFormat('en-US', { style: 'currency', currency: d.currency })
    .format(value / (d.currency === 'XOF' ? 1 : 100));
  const cell = (label, amount) => `<tr><td>${escape(label)}</td><td>${escape(money(amount))}</td></tr>`;
  res.type('html').send(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>D2F invoice</title><style>
    *{box-sizing:border-box}body{margin:0;padding:24px 14px;background:#f4f7f5;color:#13252d;font:16px/1.5 system-ui,sans-serif}
    main{max-width:700px;margin:auto;background:white;padding:clamp(20px,6vw,52px);border:1px solid #dbe5e1;border-radius:18px}
    header{border-bottom:2px solid #153f40;padding-bottom:16px}h1{margin:4px 0;font-size:2rem}p{margin:4px 0;overflow-wrap:anywhere}
    .service{color:#276255;font-weight:700}.status{margin-top:12px;font-weight:700}
    .people{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,180px),1fr));gap:16px;margin:26px 0}
    small{display:block;font-weight:700;color:#40615e}table{width:100%;border-collapse:collapse;margin-top:20px}
    th,td{text-align:left;padding:10px 0;border-bottom:1px solid #dbe5e1;overflow-wrap:anywhere}
    th:last-child,td:last-child{text-align:right;white-space:nowrap;padding-left:14px}tfoot td{font-weight:750;border-bottom:0}footer{margin-top:26px;color:#40615e;font-size:.85rem}
    @media print{body{padding:0;background:white}main{border:0;max-width:none}}
    </style></head><body><main><header><p class="service">${escape(d.service)}</p><h1>Invoice</h1>
    <p>${escape(d.number)}</p><p>Issued ${escape(d.issuedAt.slice(0, 10))}</p><p class="status">${escape(d.status)}</p></header>
    <section class="people"><div><small>ISSUED BY</small><p>${escape(d.issuer)}</p><p>${escape(d.issuerLocation)}</p></div><div><small>BILLED TO</small><p>${escape(d.buyer)}</p></div></section>
    <p><strong>Reference</strong> ${escape(d.reference)}</p>${d.route ? `<p>${escape(d.route)}</p>` : ''}
    <table><thead><tr><th scope="col">Description</th><th scope="col">${escape(d.currency)}</th></tr></thead>
    <tbody>${d.lines.map(item => cell(item.label, item.amountMinor)).join('')}</tbody>
    <tfoot>${cell('Invoice total', d.totalMinor)}${d.refundsMinor ? cell('Confirmed refunds', d.refundsMinor) : ''}</tfoot></table>
    <footer>D2F Shipping</footer></main></body></html>`);
}));

router.get('/:type/:id', authorized, wrap(async (req, res) => {
  res.set('Cache-Control', 'private, no-store').json(await authenticatedInvoice(req));
}));
router.post('/:type/:id/share', authorized, wrap(async (req, res) => {
  await authenticatedInvoice(req);
  const share = jwt.sign({ purpose: 'invoice-share', type: req.params.type, invoiceId: req.params.id }, JWT_SECRET, { expiresIn: '7d' });
  res.set('Cache-Control', 'private, no-store').json({ path: `/invoices/view/${share}` });
}));

router.put('/shipment/:id', authenticate, requireRole('ADMIN'), wrap(async (req, res) => {
  const { amountMinor, currency, paymentReference } = req.body || {};
  if (!validText(req.params.id, 160) || (paymentReference != null && !validText(paymentReference, 120))) fail(400, 'Enter a valid shipment and verified payment reference.');
  const organizationId = await resolveOrganizationId(prisma, req.user);
  const proofHash = paymentReference && createHash('sha256').update(paymentReference.trim()).digest('hex');
  const saved = await prisma.$transaction(async tx => {
    await warehouseLock(tx, organizationId);
    const p = await tx.parcel.findFirst({ where: { id: req.params.id, organizationId }, include: parties });
    if (!p || !printable.has(p.serviceType)) fail(404, 'This shipment uses a separate service invoice.');
    if (['REJECTED', 'CANCELLED'].includes(p.status)) fail(409, 'This shipment is closed to new billing.');
    const existing = p.shipmentInvoice;
    if (existing && amountMinor != null && (existing.amountMinor !== amountMinor || existing.currency !== currency)) fail(409, 'Issued charges are locked.');
    if (!existing && (!validAmount(amountMinor) || !currencies.includes(currency))) fail(400, 'Record the agreed shipping charge and currency.');
    if (existing?.paidAt && paymentReference && proofHash !== existing.proofHash) fail(409, 'Payment is already recorded for this invoice.');
    if (existing && (!paymentReference || existing.paidAt)) return existing;
    const date = new Date().toISOString();
    const document = {
      ...(existing || {
        number: `D2F-SH-${p.trackingId}`, amountMinor, currency, issuedAt: date,
        service: p.serviceType.replaceAll('_', ' '), route: `${p.origin} → ${p.destination}`,
        issuer: p.organization.name, buyer: p.customer.displayName,
      }),
      ...(paymentReference && { paidAt: date, proofHash }),
    };
    await tx.parcel.update({ where: { id: p.id }, data: { shipmentInvoice: document } });
    await tx.auditLog.create({ data: {
      actorId: req.user.id, entity: 'Parcel', entityId: p.id,
      action: paymentReference ? 'SHIPMENT_PAYMENT_RECORDED' : 'SHIPMENT_INVOICE_ISSUED',
      detail: JSON.stringify({ number: document.number, amountMinor: document.amountMinor, currency: document.currency, ...(paymentReference && { paymentReference: paymentReference.trim() }) }),
    } });
    return document;
  });
  res.json({ number: saved.number, paid: Boolean(saved.paidAt) });
}));

export default router;
