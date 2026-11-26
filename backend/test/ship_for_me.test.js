import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import jwt from 'jsonwebtoken';
import app from '../src/app.js';
import { prisma } from '../src/db.js';
import { JWT_SECRET } from '../src/config.js';

test('Ship For Me requires the displayed terms version and remembers acceptance', async t => {
  const suffix = randomUUID();
  const org = await prisma.organization.create({ data: { name: `Ship QA ${suffix}`, trackingPrefix: `Q${suffix.replaceAll('-', '').slice(0, 4).toUpperCase()}` } });
  const user = await prisma.user.create({ data: { organizationId: org.id, email: `ship-${suffix}@example.test`, fullName: 'Ship QA', passwordHash: 'unused', role: 'CUSTOMER' } });
  const customer = await prisma.customer.create({ data: { organizationId: org.id, userId: user.id, displayName: user.fullName } });
  const admin = await prisma.user.create({
    data: { organizationId: org.id, email: `ship-admin-${suffix}@example.test`, fullName: 'Ship Admin', passwordHash: 'unused', role: 'ADMIN' },
  });
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const token = jwt.sign({ id: user.id, purpose: 'session', ver: 0 }, JWT_SECRET);
  const req = async (path, method = 'GET', data) => {
    const response = await fetch(`http://127.0.0.1:${server.address().port}/ship-for-me${path}`, { method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, ...(data ? { body: JSON.stringify(data) } : {}) });
    return { status: response.status, body: await response.json() };
  };
  let agreement;
  try {
    agreement = await prisma.customerAgreement.create({ data: { version: `qa-${suffix}`, title: 'QA terms', content: 'Synthetic test terms.', serviceType: 'SHIP_FOR_ME', effectiveFrom: new Date() } });
    await prisma.warehouseAddress.create({ data: { organizationId: org.id, label: 'QA warehouse', addressLine1: '1 Test St', city: 'Omaha', country: 'United States', postalCode: '68102', isDefault: true } });
    await t.test('terms start unaccepted and stale versions are rejected', async () => {
      const terms = await req('/terms');
      assert.equal(terms.status, 200);
      assert.equal(terms.body.id, agreement.id);
      assert.equal(terms.body.accepted, false);
      assert.equal((await req('/terms/accept', 'POST', { agreementId: agreement.id, version: 'outdated' })).status, 409);
      assert.equal((await req('/terms')).body.accepted, false);
    });
    await t.test('acceptance enables registration and survives reloading', async () => {
      const input = { retailerName: 'QA retailer', itemDescription: 'Test shoes', declaredValueMinor: 2500, declaredCurrency: 'USD' };
      assert.equal((await req('/requests', 'POST', input)).status, 403);
      const accepted = await req('/terms/accept', 'POST', { agreementId: agreement.id, version: agreement.version });
      assert.equal(accepted.status, 200);
      assert.equal((await req('/terms/accept', 'POST', { agreementId: agreement.id, version: agreement.version })).body.acceptedAt, accepted.body.acceptedAt);
      const originalReference = (await req('/warehouse-address')).body.customerWarehouseId;
      assert.equal((await req('/terms')).body.accepted, true);
      const created = await req('/requests', 'POST', input);
      assert.equal(created.status, 201, JSON.stringify(created.body));
      assert.equal(created.body.agreementVersion, agreement.version);
      assert.equal(created.body.customerWarehouseId, originalReference);
      assert.equal((await req('/warehouse-address')).body.customerWarehouseId, originalReference);
      assert.equal(created.body.status, 'DRAFT');
      assert.equal((await req('/requests')).body.length, 1);
    });
    await t.test('receipt, itemized shipping quote and verified payment become a shareable invoice', async () => {
      const base = `http://127.0.0.1:${server.address().port}`;
      const bearer = who => jwt.sign({ id: who.id, purpose: 'session', ver: 0 }, JWT_SECRET);
      const call = (path, who, method = 'GET', body) => fetch(base + path, {
        method, headers: { ...(who && { Authorization: `Bearer ${bearer(who)}` }), 'Content-Type': 'application/json' },
        ...(body && { body: JSON.stringify(body) }),
      });
      const order = (await req('/requests')).body[0];
      const quotePath = `/admin/commerce/services/ship-for-me/quotes/${order.id}`;
      const invoicePath = `/invoices/ship-for-me/${order.id}`;
      const quote = { shippingFeeMinor: 4500, insuranceFeeMinor: 300, handlingFeeMinor: 200, weightKg: 4, received: true, method: 'SEA' };
      assert.equal((await req(`/requests/${order.id}/submit`, 'POST', { retailerTrackingId: 'SHIP-TEST' })).status, 200);
      assert.equal((await call(quotePath, user, 'PUT', quote)).status, 403);
      assert.equal((await call(quotePath, admin, 'PUT', { ...quote, received: false })).status, 400);
      assert.equal((await call(quotePath, admin, 'PUT', quote)).status, 200);
      assert.equal((await call(invoicePath, user)).status, 404);
      const offered = (await req('/requests')).body[0];
      const accept = `/requests/${order.id}/accept-quote`;
      assert.equal((await req(accept, 'POST', { totalMinor: 4500, updatedAt: offered.updatedAt })).status, 409);
      assert.equal((await req(accept, 'POST', { totalMinor: 5000, updatedAt: offered.updatedAt })).status, 200);
      assert.equal((await call(quotePath, admin, 'PUT', quote)).status, 409);
      const invoice = await (await call(invoicePath, user)).json();
      assert.deepEqual(invoice.lines.map(line => line.amountMinor), [4500, 300, 200]);
      assert.equal(invoice.totalMinor, 5000);
      assert.equal(invoice.status, 'Awaiting payment');
      const payment = { reference: 'SHIP-REF-TEST', amountMinor: 5000 };
      assert.equal((await call(`${quotePath}/payment`, admin, 'POST', payment)).status, 200);
      assert.equal((await call(`${quotePath}/payment`, admin, 'POST', payment)).status, 200);
      assert.equal(await prisma.payment.count({ where: { shipForMeRequestId: order.id } }), 1);
      const shared = await (await call(`${invoicePath}/share`, user, 'POST')).json();
      const publicPage = await call(shared.path, null);
      assert.equal(publicPage.status, 200);
      assert.equal(publicPage.headers.get('cache-control'), 'private, no-store');
      const html = await publicPage.text();
      assert.match(html, /Paid/);
      assert.match(html, /\$50\.00/);
      assert.doesNotMatch(html, /SHIP-REF-TEST/);
      const expired = jwt.sign({ purpose: 'invoice-share', type: 'ship-for-me', invoiceId: order.id }, JWT_SECRET, { expiresIn: -1 });
      assert.equal((await call(`/invoices/view/${expired}`, null)).status, 404);
      assert.equal((await call(invoicePath, null)).status, 401);
    });
    await t.test('removing acceptance requires agreement again', async () => {
      await prisma.customerAgreementAcceptance.deleteMany({ where: { customerId: customer.id } });
      assert.equal((await req('/terms')).body.accepted, false);
    });
  } finally {
    await prisma.shipForMeRequest.deleteMany({ where: { organizationId: org.id } });
    await prisma.customer.deleteMany({ where: { id: customer.id } });
    await prisma.warehouseAddress.deleteMany({ where: { organizationId: org.id } });
    if (agreement) await prisma.customerAgreement.delete({ where: { id: agreement.id } });
    await prisma.auditLog.deleteMany({ where: { actorId: { in: [user.id, admin.id] } } });
    await prisma.user.deleteMany({ where: { id: { in: [user.id, admin.id] } } });
    await prisma.organization.delete({ where: { id: org.id } });
    await new Promise(resolve => server.close(resolve));
    await prisma.$disconnect();
  }
});
