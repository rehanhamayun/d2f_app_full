import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID, randomBytes } from 'node:crypto';
import jwt from 'jsonwebtoken';
import app from '../src/app.js';
import { prisma } from '../src/db.js';
import { JWT_SECRET } from '../src/config.js';

test('Admin parcel corrections preserve identity, tenancy, history and warehouse rules', async t => {
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const suffix = randomUUID(), organizations = [], users = [];
  const req = async (path, actor, method = 'GET', body) => {
    const response = await fetch(`${base}${path}`, { method, headers: {
      'Content-Type': 'application/json',
      ...(actor ? { Authorization: `Bearer ${jwt.sign({ id: actor.id, purpose: 'session', ver: 0 }, JWT_SECRET)}` } : {}),
    }, ...(body ? { body: JSON.stringify(body) } : {}) });
    return { status: response.status, body: await response.json() };
  };
  const ok = (result, status = 200) => { assert.equal(result.status, status, JSON.stringify(result.body)); return result.body; };
  try {
    for (let i = 0; i < 2; i++) organizations.push(await prisma.organization.create({ data: { name: `Parcel edit QA ${suffix}-${i}`, trackingPrefix: `E${randomBytes(2).toString('hex').toUpperCase()}` } }));
    const [org, foreign] = organizations;
    const intake = await prisma.location.create({ data: {
      organizationId: org.id, name: 'Edit Intake', code: 'INT', city: 'Omaha', country: 'United States',
    } });
    for (const [role, organizationId] of [['ADMIN', org.id], ['STAFF', org.id], ['CUSTOMER', org.id], ['DRIVER', org.id], ['ADMIN', foreign.id]]) users.push(await prisma.user.create({ data: { email: `${role}-${organizationId}-${suffix}@example.test`, fullName: `Edit QA ${role}`, passwordHash: 'unused', role, organizationId, ...(role === 'STAFF' ? { locationId: intake.id } : {}) } }));
    const [admin, staff, customerUser, driver, foreignAdmin] = users;
    const profile = ok(await req('/customers', admin, 'POST', { displayName: 'Original customer' }), 201);
    const replacement = ok(await req('/customers', admin, 'POST', { displayName: 'Corrected customer' }), 201);
    const foreignProfile = ok(await req('/customers', foreignAdmin, 'POST', { displayName: 'Other organization customer' }), 201);
    let parcel = ok(await req('/parcels', staff, 'POST', { customerId: profile.id, recipientName: 'Typo', packageType: 'BOX', weightKg: 1, origin: 'Omaha, NE, USA', destination: 'Lomé, Togo', method: 'SEA', clientRequestId: suffix }), 201);
    const path = `/parcels/${parcel.id}`;
    const original = structuredClone(parcel);
    const patch = (body, actor = admin) => req(path, actor, 'PATCH', { updatedAt: parcel.updatedAt, ...body });

    await t.test('only an authenticated Admin in the owning organization can edit', async () => {
      ok(await patch({ recipientName: 'Denied' }, null), 401);
      for (const actor of [staff, customerUser, driver]) ok(await patch({ recipientName: 'Denied' }, actor), 403);
      ok(await patch({ recipientName: 'Denied' }, foreignAdmin), 404);
      ok(await patch({ customerId: foreignProfile.id }), 404);
      ok(await req('/parcels/missing', admin, 'PATCH', { recipientName: 'Missing', updatedAt: parcel.updatedAt }), 404);
    });
    await t.test('invalid inputs and protected fields leave the record untouched', async () => {
      for (const body of [
        { recipientName: '' }, { recipientName: '  ' }, { recipientName: {} }, { recipientName: 'a'.repeat(121) },
        { customerId: null }, { recipientPhone: 42 }, { recipientAddress: [] }, { notes: false },
        { origin: '' }, { destination: null }, { packageType: 'INVALID' }, { method: 'INVALID' },
        { weightKg: 0 }, { weightKg: -1 }, { weightKg: null }, { weightKg: true }, { weightKg: 'NaN' }, { weightKg: 10001 },
        { status: 'DELIVERED' }, { trackingId: 'NEW' }, { organizationId: foreign.id }, { containerId: 'bad' },
        { updatedAt: null, recipientName: 'New' }, { updatedAt: 'invalid', recipientName: 'New' }, {},
      ]) ok(await patch(body), 400);
      assert.equal((await prisma.parcel.findUnique({ where: { id: parcel.id } })).recipientName, 'Typo');
      assert.equal(await prisma.auditLog.count({ where: { entityId: parcel.id, action: 'PARCEL_EDIT' } }), 0);
    });
    await t.test('all input corrections persist with an actor and before/after audit while identity and events remain', async () => {
      parcel = ok(await patch({ customerId: replacement.id, recipientName: ' Correct Recipient ', recipientPhone: ' +228 90000000 ', recipientAddress: ' Correct address ', packageType: 'BARREL', weightKg: 12.5, origin: ' Omaha, USA ', destination: ' Lomé, Togo ', method: 'AIR', notes: ' Corrected intake ' }));
      assert.equal(parcel.recipientName, 'Correct Recipient');
      assert.equal(parcel.recipientAddress, 'Correct address');
      assert.equal(parcel.recipientPhone, '+228 90000000');
      assert.equal(parcel.weightKg, 12.5); assert.equal(parcel.packageType, 'BARREL');
      assert.equal(parcel.customer.id, replacement.id); assert.equal(parcel.customer.displayName, 'Corrected customer');
      for (const field of ['id', 'trackingId', 'status', 'createdAt', 'createdById', 'clientRequestId']) assert.equal(parcel[field], original[field]);
      assert.equal(parcel.events.length, 1); assert.equal(parcel.events[0].note, 'Parcel registered at intake');
      assert.equal((await prisma.trackingIndex.findUnique({ where: { trackingId: parcel.trackingId } })).parcelId, parcel.id);
      const audit = await prisma.auditLog.findFirstOrThrow({ where: { entityId: parcel.id, action: 'PARCEL_EDIT' } });
      assert.equal(audit.actorId, admin.id);
      assert.deepEqual(JSON.parse(audit.detail).changes.recipientName, { from: 'Typo', to: 'Correct Recipient' });
      parcel = ok(await patch({ recipientPhone: '', recipientAddress: null, notes: '  ' }));
      for (const field of ['recipientPhone', 'recipientAddress', 'notes']) assert.equal(parcel[field], null);
    });
    await t.test('concurrent and stale saves cannot overwrite newer edits', async () => {
      const results = await Promise.all([patch({ notes: 'First admin' }), patch({ notes: 'Second admin' })]);
      assert.deepEqual(results.map(r => r.status).sort(), [200, 409]);
      ok(await patch({ notes: 'Stale overwrite' }), 409);
      parcel = ok(await req(path, admin));
      assert.ok(['First admin', 'Second admin'].includes(parcel.notes));
      const auditCount = await prisma.auditLog.count({ where: { entityId: parcel.id, action: 'PARCEL_EDIT' } });
      parcel = ok(await patch({ notes: parcel.notes }));
      assert.equal(await prisma.auditLog.count({ where: { entityId: parcel.id, action: 'PARCEL_EDIT' } }), auditCount);
    });
    await t.test('loaded routes are protected, draft manifests reflect corrections and departure manifests stay frozen', async () => {
      parcel = ok(await patch({ method: 'SEA' }));
      const location = async (name, code, city, country) => ok(await req('/warehouse/locations', admin, 'POST', { name, code, city, country }), 201);
      const origin = await location('QA Omaha', 'OMA', 'Omaha', 'United States');
      const destination = await location('QA Lomé', 'LOM', 'Lomé', 'Togo');
      await prisma.user.update({ where: { id: staff.id }, data: { locationId: origin.id } });
      const container = ok(await req('/warehouse/containers', staff, 'POST', { code: `EDIT-${suffix.slice(0, 8)}`, originId: origin.id, destinationId: destination.id, method: 'SEA' }), 201);
      await prisma.parcel.update({ where: { id: parcel.id }, data: { locationId: origin.id } });
      parcel = ok(await req(path, admin));
      ok(await req(`/warehouse/containers/${container.id}/parcels`, staff, 'POST', { trackingId: parcel.trackingId, loadingConfirmed: true }), 201);
      parcel = ok(await req(path, admin));
      for (const body of [{ method: 'AIR' }, { origin: 'Paris, France' }, { destination: 'Accra, Ghana' }]) ok(await patch(body), 409);
      parcel = ok(await patch({ recipientName: 'Warehouse correction', weightKg: 15 }));
      const manifestPath = `/warehouse/containers/${container.id}/manifest`;
      const draft = ok(await req(manifestPath, staff));
      assert.equal(draft.totalWeightKg, 15); assert.equal(draft.parcels[0].recipientName, 'Warehouse correction');
      ok(await req(`/warehouse/containers/${container.id}/events`, staff, 'POST', { action: 'DEPARTED' }), 201);
      const frozen = ok(await req(manifestPath, staff));
      parcel = ok(await req(path, admin));
      parcel = ok(await patch({ recipientPhone: '+228 91111111', weightKg: 16 }));
      assert.equal(parcel.status, 'IN_TRANSIT');
      assert.deepEqual(ok(await req(manifestPath, staff)), frozen);
    });
    await t.test('a linked shopping order prevents changing shipment ownership', async () => {
      await prisma.serviceOrder.create({ data: { organizationId: org.id, customerId: replacement.id, parcelId: parcel.id, kind: 'BUY_FOR_ME', title: 'Linked order', currency: 'USD' } });
      ok(await patch({ customerId: profile.id }), 409);
      assert.equal((await prisma.parcel.findUnique({ where: { id: parcel.id } })).customerId, replacement.id);
    });
  } finally {
    const ids = organizations.map(o => o.id), actorIds = users.map(u => u.id);
    const parcels = await prisma.parcel.findMany({ where: { organizationId: { in: ids } }, select: { id: true } });
    const containers = await prisma.container.findMany({ where: { organizationId: { in: ids } }, select: { id: true } });
    await prisma.serviceOrder.deleteMany({ where: { organizationId: { in: ids } } });
    await prisma.trackingEvent.deleteMany({ where: { parcelId: { in: parcels.map(p => p.id) } } });
    await prisma.trackingIndex.deleteMany({ where: { parcelId: { in: parcels.map(p => p.id) } } });
    await prisma.parcel.deleteMany({ where: { organizationId: { in: ids } } });
    await prisma.containerEvent.deleteMany({ where: { containerId: { in: containers.map(c => c.id) } } });
    await prisma.container.deleteMany({ where: { organizationId: { in: ids } } });
    await prisma.auditLog.deleteMany({ where: { actorId: { in: actorIds } } });
    await prisma.customer.deleteMany({ where: { organizationId: { in: ids } } });
    await prisma.user.deleteMany({ where: { id: { in: actorIds } } });
    await prisma.location.deleteMany({ where: { organizationId: { in: ids } } });
    await prisma.organization.deleteMany({ where: { id: { in: ids } } });
    await new Promise(resolve => server.close(resolve));
    await prisma.$disconnect();
  }
});
