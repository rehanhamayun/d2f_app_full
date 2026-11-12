import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import jwt from 'jsonwebtoken';
import app from '../src/app.js';
import { prisma } from '../src/db.js';
import { JWT_SECRET } from '../src/config.js';
import { drainPush } from '../src/push.js';

test('operation alerts commit atomically, reach the correct accounts and retry independently per device', async () => {
  const id = randomUUID();
  const org = await prisma.organization.create({ data: { name: id, trackingPrefix: 'N' + id.replaceAll('-', '').slice(0, 4).toUpperCase() } });
  const makeUser = (role) => prisma.user.create({ data: { email: `${role}-${id}@example.test`, fullName: role, passwordHash: 'test', role, organizationId: org.id } });
  const admin = await makeUser('ADMIN'), user = await makeUser('CUSTOMER');
  const customer = await prisma.customer.create({ data: { displayName: 'Buyer', userId: user.id, organizationId: org.id } });
  const server = app.listen(0, '127.0.0.1'); await new Promise(r => server.once('listening', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = (path, who, method, data) => fetch(base + path, { method, headers: { Authorization: `Bearer ${jwt.sign({ id: who.id, purpose: 'session', ver: 0 }, JWT_SECRET)}`, 'Content-Type': 'application/json' }, body: data ? JSON.stringify(data) : undefined });
  try {
    assert.equal((await call('/notifications/devices', user, 'PUT', { token: 'a', platform: 'android' })).status, 400);
    const tokens = ['push-device-one-' + id, 'push-device-two-' + id];
    for (const token of tokens) assert.equal((await call('/notifications/devices', user, 'PUT', { token, platform: 'android' })).status, 200);
    const order = await prisma.serviceOrder.create({ data: { organizationId: org.id, customerId: customer.id, kind: 'BUY_FOR_ME', title: 'Laptop', status: 'REQUESTED', source: 'APP' } });
    assert.equal(await prisma.notification.count({ where: { userId: user.id, entityId: order.id } }), 1);
    assert.equal(await prisma.notification.count({ where: { userId: admin.id, entityId: order.id } }), 1);
    const before = await prisma.notification.count({ where: { userId: user.id } });
    await assert.rejects(prisma.$transaction(async tx => { await tx.serviceOrder.update({ where: { id: order.id }, data: { status: 'QUOTED', amountMinor: 12000 } }); throw new Error('rollback'); }), /rollback/);
    assert.equal(await prisma.notification.count({ where: { userId: user.id } }), before);
    await prisma.serviceOrder.update({ where: { id: order.id }, data: { notes: 'PRIVATE STAFF NOTE' } });
    assert.equal(await prisma.notification.count({ where: { userId: user.id } }), before);
    await prisma.serviceOrder.update({ where: { id: order.id }, data: { status: 'QUOTED', amountMinor: 12000 } });
    const db = {
      notification: { findMany: args => prisma.notification.findMany({ ...args, where: { ...args.where, userId: user.id } }) },
      $transaction: fn => prisma.$transaction(fn),
      pushDevice: prisma.pushDevice,
      pushDelivery: { ...prisma.pushDelivery, findMany: args => prisma.pushDelivery.findMany({ ...args, where: { ...args.where, notification: { userId: user.id } } }) },
    };
    const sent = [];
    let failing = true;
    const messaging = { send: async payload => {
      if (!tokens.includes(payload.token)) return;
      if (payload.token === tokens[1] && failing) throw Object.assign(new Error('temporary outage'), { code: 'messaging/server-unavailable' });
      sent.push(payload);
    } };
    await drainPush({ db, messaging });
    assert.equal(sent.filter(p => p.token === tokens[0]).length, 2);
    assert.equal(sent.filter(p => p.token === tokens[1]).length, 0);
    failing = false;
    await drainPush({ db, messaging, now: new Date(Date.now() + 120000) });
    assert.equal(sent.filter(p => p.token === tokens[0]).length, 2, 'successful devices must not be sent retries');
    assert.equal(sent.filter(p => p.token === tokens[1]).length, 2);
    assert.equal(sent[0].data.entityId, order.id);
    assert.ok(sent.every(p => !JSON.stringify(p).includes('PRIVATE STAFF NOTE')));
    // Reassigning a shared device prevents pending alerts from crossing accounts.
    await prisma.serviceOrder.update({ where: { id: order.id }, data: { status: 'ACCEPTED' } });
    await call('/notifications/devices', admin, 'PUT', { token: tokens[0], platform: 'android' });
    await drainPush({ db, messaging });
    assert.equal(sent.filter(p => p.token === tokens[0] && p.notification.title === 'Buy for ME').length, 2);
    const all = await (await call('/notifications', user, 'GET')).json();
    assert.ok(all.unread > 0);
    await call('/notifications/read-all', user, 'POST');
    assert.equal((await (await call('/notifications/unread-count', user, 'GET')).json()).unread, 0);
    const sentBeforeDisable = sent.length;
    await prisma.serviceOrder.update({ where: { id: order.id }, data: { status: 'CANCELLED' } });
    await prisma.user.update({ where: { id: user.id }, data: { isActive: false } });
    await drainPush({ db, messaging });
    assert.equal(sent.length, sentBeforeDisable, 'deactivated accounts must not receive queued pushes');
    await prisma.user.update({ where: { id: user.id }, data: { isActive: true } });
    await prisma.notification.create({ data: { userId: user.id, type: 'TEST', title: 'Device cleanup' } });
    await drainPush({ db, messaging: { send: async () => { throw Object.assign(new Error('invalid token'), { code: 'messaging/registration-token-not-registered' }); } } });
    assert.equal(await prisma.pushDevice.count({ where: { userId: user.id } }), 0, 'expired device tokens are removed');
    await call('/notifications/devices', user, 'DELETE', { token: tokens[1] });
    assert.equal(await prisma.pushDevice.count({ where: { userId: user.id } }), 0);
  } finally {
    await new Promise(r => server.close(r));
    await prisma.serviceOrder.deleteMany({ where: { organizationId: org.id } });
    await prisma.customer.deleteMany({ where: { organizationId: org.id } });
    await prisma.user.deleteMany({ where: { organizationId: org.id } });
    await prisma.organization.delete({ where: { id: org.id } });
  }
});
