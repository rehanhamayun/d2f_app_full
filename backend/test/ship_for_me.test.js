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
      assert.equal((await req('/terms/accept', 'POST', { agreementId: agreement.id, version: agreement.version })).status, 200);
      assert.equal((await req('/terms')).body.accepted, true);
      const created = await req('/requests', 'POST', input);
      assert.equal(created.status, 201, JSON.stringify(created.body));
      assert.equal(created.body.agreementVersion, agreement.version);
      assert.equal(created.body.status, 'DRAFT');
      assert.equal((await req('/requests')).body.length, 1);
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
    await prisma.auditLog.deleteMany({ where: { actorId: user.id } });
    await prisma.user.delete({ where: { id: user.id } });
    await prisma.organization.delete({ where: { id: org.id } });
    await new Promise(resolve => server.close(resolve));
    await prisma.$disconnect();
  }
});
