import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import jwt from 'jsonwebtoken';
import app from '../src/app.js';
import { prisma } from '../src/db.js';
import { JWT_SECRET } from '../src/config.js';

test('purchase retries are safe, tenant-scoped and quote acceptance protects the displayed price', async () => {
  const suffix = randomUUID();
  const org = await prisma.organization.create({ data: { name: suffix, trackingPrefix: 'B' + suffix.replaceAll('-', '').slice(0, 4).toUpperCase() } });
  const users = [];
  const server = app.listen(0, '127.0.0.1'); await new Promise(r => server.once('listening', r));
  const call = async (user, path, body, method = 'POST') => {
    const response = await fetch(`http://127.0.0.1:${server.address().port}${path}`, { method, headers: { Authorization: `Bearer ${jwt.sign({ id: user.id, purpose: 'session', ver: 0 }, JWT_SECRET)}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    return { status: response.status, body: await response.json() };
  };
  try {
    for (let n = 0; n < 2; n++) users.push(await prisma.user.create({ data: { email: `${n}-${suffix}@example.test`, fullName: 'Purchase buyer', passwordHash: 'unused', role: 'CUSTOMER', organizationId: org.id } }));
    const payload = { clientRequestId: 'retry-' + suffix, title: 'A laptop and carrying case', quantity: 1, budgetMinor: 100000, currency: 'USD', deliveryAddress: '123 Example Street', deliveryCity: 'Lomé', deliveryCountry: 'Togo', deliveryPostalCode: '00000' };
    const attempts = await Promise.all([call(users[0], '/buy-for-me/requests', payload), call(users[0], '/buy-for-me/requests', payload)]);
    assert.deepEqual(attempts.map(r => r.status).sort(), [200, 201]);
    assert.equal(attempts[0].body.id, attempts[1].body.id);
    assert.equal(attempts[1].body.customerId, undefined);
    const orderId = attempts[0].body.id;
    assert.equal(await prisma.serviceOrder.count({ where: { organizationId: org.id } }), 1);
    assert.equal(await prisma.notification.count({ where: { userId: users[0].id, entityId: orderId } }), 1);
    assert.equal((await call(users[0], '/buy-for-me/requests', { ...payload, title: 'Changed item after uncertain response' })).status, 409);
    assert.equal((await call(users[1], '/buy-for-me/requests', payload)).status, 409);
    await prisma.serviceOrder.update({ where: { id: orderId }, data: { status: 'QUOTED', productCostMinor: 90000, shippingCostMinor: 10000, amountMinor: 100000 } });
    assert.equal((await call(users[0], `/buy-for-me/requests/${orderId}/accept`, { expectedAmountMinor: 95000, expectedCurrency: 'USD' })).status, 409);
    assert.equal((await call(users[0], `/buy-for-me/requests/${orderId}/accept`, { expectedAmountMinor: 100000, expectedCurrency: 'EUR' })).status, 409);
    assert.equal((await prisma.serviceOrder.findUnique({ where: { id: orderId } })).status, 'QUOTED');
    assert.equal((await call(users[0], `/buy-for-me/requests/${orderId}/accept`, { expectedAmountMinor: 100000, expectedCurrency: 'USD' })).status, 200);
    // Legacy clients without a retry key still work while installed apps update.
    const { clientRequestId, ...legacy } = payload;
    assert.equal((await call(users[0], '/buy-for-me/requests', legacy)).status, 201);
  } finally {
    await new Promise(r => server.close(r));
    await prisma.serviceOrder.deleteMany({ where: { organizationId: org.id } });
    await prisma.auditLog.deleteMany({ where: { actorId: { in: users.map(u => u.id) } } });
    await prisma.customer.deleteMany({ where: { organizationId: org.id } });
    await prisma.user.deleteMany({ where: { organizationId: org.id } });
    await prisma.organization.delete({ where: { id: org.id } });
  }
});
