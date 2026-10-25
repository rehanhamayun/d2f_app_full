import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID, randomBytes } from 'node:crypto';
import jwt from 'jsonwebtoken';
import app from '../src/app.js';
import { prisma } from '../src/db.js';
import { JWT_SECRET } from '../src/config.js';

// Real API/database tests. All rows belong to fresh isolated organizations.
test('M2: warehouse, two-way freight, permissions and selected revenue modules', async t => {
  const server = app.listen(0, '127.0.0.1');
  await new Promise(r => server.once('listening', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const suffix = randomUUID(), organizations = [], users = [], parcelIds = [];
  const token = user => jwt.sign({ id: user.id, purpose: 'session', ver: 0 }, JWT_SECRET);
  const req = async (path, user, method = 'GET', data) => {
    const response = await fetch(`${base}${path}`, { method, headers: { 'Content-Type': 'application/json', ...(user ? { Authorization: `Bearer ${token(user)}` } : {}) }, ...(data ? { body: JSON.stringify(data) } : {}) });
    return { status: response.status, body: await response.json() };
  };
  const expectStatus = (result, status) => { assert.equal(result.status, status, JSON.stringify(result.body)); return result.body; };
  try {
    for (let i = 0; i < 2; i++) organizations.push(await prisma.organization.create({ data: { name: `M2 QA ${suffix}-${i}`, trackingPrefix: `Q${randomBytes(2).toString('hex').toUpperCase()}` } }));
    const org = organizations[0], otherOrg = organizations[1];
    for (const [role, organizationId] of [['ADMIN', org.id], ['STAFF', org.id], ['CUSTOMER', org.id], ['DRIVER', org.id], ['ADMIN', otherOrg.id]]) users.push(await prisma.user.create({ data: { email: `${role}-${organizationId}-${suffix}@example.test`, fullName: `M2 ${role}`, passwordHash: 'unused', role, organizationId } }));
    const [admin, staff, customerUser, driver, foreignAdmin] = users;
    let omaha, lome, brussels, profile, foreignProfile, container, competing, outboundParcel, returnParcel, otherParcel;
    await t.test('operational routes reject anonymous, customer and driver access; commerce is Admin only', async () => {
      for (const actor of [null, customerUser, driver]) for (const path of ['/warehouse/containers', '/warehouse/locations', '/admin/commerce/marketplace']) expectStatus(await req(path, actor), actor ? 403 : 401);
      expectStatus(await req('/admin/commerce/buy_for_me', staff), 403);
      expectStatus(await req('/admin/users', staff), 403);
      for (const path of ['/warehouse/directory/parcels', '/warehouse/directory/customers']) {
        expectStatus(await req(path, staff), 200);
        expectStatus(await req(path, customerUser), 403);
      }
      expectStatus(await req('/warehouse/locations', staff, 'POST', {}), 403);
    });
    await t.test('Admin manages service-area facilities, customer profiles and team locations', async () => {
      const create = async (name, code, city, country) => expectStatus(await req('/warehouse/locations', admin, 'POST', { name, code, city, country }), 201);
      omaha = await create('Omaha Warehouse', 'OMA-QA', 'Omaha, NE', 'United States');
      lome = await create('Lomé Facility', 'LOM-QA', 'Lomé', 'Togo');
      brussels = await create('Brussels Facility', 'BRU-QA', 'Brussels', 'Belgium');
      expectStatus(await req('/warehouse/locations', admin, 'POST', { name: 'Outside scope', code: 'BAD', city: 'Sydney', country: 'Australia' }), 400);
      expectStatus(await req('/warehouse/locations', admin, 'POST', { name: {}, code: 'BAD', city: 'Omaha', country: 'United States' }), 400);
      expectStatus(await req('/warehouse/locations', admin, 'POST', { name: 'Timezone check', code: 'TZ', city: 'Omaha', country: 'United States', timezone: 'Invalid/Zone' }), 400);
      const foreignLocation = expectStatus(await req('/warehouse/locations', foreignAdmin, 'POST', { name: 'Foreign', code: 'FOREIGN', city: 'Paris', country: 'France' }), 201);
      expectStatus(await req(`/admin/users/${staff.id}/location`, admin, 'PATCH', { locationId: foreignLocation.id }), 400);
      const assigned = expectStatus(await req(`/admin/users/${staff.id}/location`, admin, 'PATCH', { locationId: omaha.id }), 200);
      assert.equal(assigned.user.location.code, 'OMA-QA');
      profile = expectStatus(await req('/customers', admin, 'POST', { displayName: 'M2 Customer', country: 'Togo' }), 201);
      foreignProfile = expectStatus(await req('/customers', foreignAdmin, 'POST', { displayName: 'Foreign Customer' }), 201);
      const saved = expectStatus(await req(`/customers/${profile.id}`, admin, 'PATCH', { displayName: 'Updated M2 Customer', country: 'Benin' }), 200);
      assert.equal(saved.country, 'Benin');
      expectStatus(await req(`/customers/${profile.id}`, staff, 'PATCH', { displayName: 'No' }), 403);
      expectStatus(await req(`/customers/${foreignProfile.id}`, admin, 'PATCH', { displayName: 'No' }), 404);
      const createParcel = async (method, origin, destination) => {
        const parcel = expectStatus(await req('/parcels', staff, 'POST', { customerId: profile.id, recipientName: 'M2 Recipient', weightKg: 2.5, packageType: 'BOX', method, origin, destination, clientRequestId: randomUUID() }), 201);
        parcelIds.push(parcel.id); return parcel;
      };
      outboundParcel = await createParcel('SEA', 'Omaha, NE, USA', 'Lomé, Togo');
      returnParcel = await createParcel('SEA', 'Lomé, Togo', 'Brussels, Belgium');
      otherParcel = await createParcel('AIR', 'Omaha, NE, USA', 'Lomé, Togo');
    });
    await t.test('container creation validates routes, unique references and tenant isolation', async () => {
      const input = { code: `QA-${suffix.slice(0, 8)}`, originId: omaha.id, destinationId: lome.id, method: 'SEA' };
      container = expectStatus(await req('/warehouse/containers', staff, 'POST', input), 201);
      competing = expectStatus(await req('/warehouse/containers', admin, 'POST', { ...input, code: `QA-OTHER-${suffix.slice(0, 8)}` }), 201);
      expectStatus(await req('/warehouse/containers', admin, 'POST', input), 409);
      expectStatus(await req('/warehouse/containers', foreignAdmin, 'POST', { ...input, code: 'ILLEGAL' }), 400);
      expectStatus(await req(`/warehouse/containers/${container.id}`, foreignAdmin), 404);
      expectStatus(await req(`/warehouse/containers/${container.id}/manifest`, foreignAdmin), 404);
      expectStatus(await req(`/warehouse/containers/${container.id}/events`, staff, 'POST', { action: 'DEPARTED' }), 409);
      expectStatus(await req('/warehouse/containers?offset=-1', staff), 400);
      const listed = expectStatus(await req(`/warehouse/containers?q=${container.code}&limit=1`, staff), 200);
      assert.equal(listed.total, 1); assert.equal(listed.containers[0].id, container.id);
      expectStatus(await req(`/warehouse/locations/${omaha.id}`, admin, 'PATCH', { name: 'Changed', code: 'OMA-NEW', city: 'Omaha', country: 'United States' }), 409);
    });
    await t.test('concurrent repeated scans load once and reject incompatible or competing assignments', async () => {
      const path = `/warehouse/containers/${container.id}/parcels`;
      const results = await Promise.all([req(path, staff, 'POST', { trackingId: outboundParcel.trackingId }), req(path, staff, 'POST', { trackingId: outboundParcel.trackingId.toLowerCase() })]);
      assert.deepEqual(results.map(r => r.status).sort(), [200, 201]);
      expectStatus(await req(`/warehouse/containers/${competing.id}/parcels`, staff, 'POST', { trackingId: outboundParcel.trackingId }), 409);
      expectStatus(await req(path, staff, 'POST', { trackingId: otherParcel.trackingId }), 409);
      expectStatus(await req(path, staff, 'POST', { trackingId: returnParcel.trackingId }), 409);
      expectStatus(await req(path, foreignAdmin, 'POST', { trackingId: outboundParcel.trackingId }), 404);
      expectStatus(await req(`/parcels/${outboundParcel.id}/events`, staff, 'POST', { status: 'IN_TRANSIT' }), 409);
      let detail = expectStatus(await req(`/warehouse/containers/${container.id}`, staff), 200);
      assert.equal(detail.parcels.length, 1); assert.equal(detail.events.filter(e => e.action === 'PARCEL_LOADED').length, 1);
      expectStatus(await req(`${path}/${outboundParcel.id}`, staff, 'DELETE'), 200);
      expectStatus(await req(path, staff, 'POST', { trackingId: outboundParcel.trackingId }), 201);
      detail = expectStatus(await req(`/parcels/${outboundParcel.id}`, staff), 200);
      assert.equal(detail.container.code, container.code);
      assert.ok(detail.events.some(e => e.note.startsWith('Removed from container')));
    });
    let finalManifest;
    await t.test('departure is atomic, concurrent-safe and freezes the printable manifest', async () => {
      const draft = expectStatus(await req(`/warehouse/containers/${container.id}/manifest`, staff), 200);
      assert.equal(draft.provisional, true); assert.equal(draft.parcelCount, 1); assert.equal(draft.totalWeightKg, 2.5);
      const results = await Promise.all([req(`/warehouse/containers/${container.id}/events`, staff, 'POST', { action: 'DEPARTED' }), req(`/warehouse/containers/${container.id}/events`, admin, 'POST', { action: 'DEPARTED' })]);
      assert.deepEqual(results.map(r => r.status).sort(), [201, 409]);
      const p = expectStatus(await req(`/parcels/${outboundParcel.id}`, staff), 200);
      assert.equal(p.status, 'IN_TRANSIT'); assert.equal(p.events.filter(e => e.status === 'IN_TRANSIT').length, 1);
      assert.ok(p.events.at(-1).note.includes('Departed Omaha'));
      finalManifest = expectStatus(await req(`/warehouse/containers/${container.id}/manifest`, staff), 200);
      assert.equal(finalManifest.provisional, false);
      expectStatus(await req(`/warehouse/containers/${container.id}/parcels`, staff, 'POST', { trackingId: returnParcel.trackingId }), 409);
      expectStatus(await req(`/warehouse/containers/${container.id}/parcels/${outboundParcel.id}`, staff, 'DELETE'), 409);
    });
    await t.test('Lomé arrival, ready, released and delivered preserve actor/time history and frozen manifest', async () => {
      expectStatus(await req(`/warehouse/containers/${container.id}/events`, staff, 'POST', { action: 'ARRIVED' }), 201);
      const p = expectStatus(await req(`/parcels/${outboundParcel.id}`, staff), 200);
      assert.equal(p.status, 'ARRIVED_LOME'); assert.equal(p.locationId, lome.id);
      for (const status of ['READY_FOR_PICKUP', 'RELEASED', 'DELIVERED']) expectStatus(await req(`/parcels/${p.id}/events`, staff, 'POST', { status, location: 'Lomé, Togo' }), 201);
      const saved = expectStatus(await req(`/parcels/${p.id}`, staff), 200);
      assert.equal(saved.status, 'DELIVERED');
      assert.ok(saved.events.every((e, i, all) => e.actor?.fullName && e.createdAt && (!i || new Date(e.createdAt) >= new Date(all[i-1].createdAt))));
      assert.deepEqual(expectStatus(await req(`/warehouse/containers/${container.id}/manifest`, admin), 200), finalManifest);
      expectStatus(await req(`/parcels/${p.id}/events`, staff, 'POST', { status: 'RECEIVED' }), 400);
    });
    await t.test('West Africa to EU freight arrives at its actual destination and can complete normally', async () => {
      const c = expectStatus(await req('/warehouse/containers', staff, 'POST', { code: `RETURN-${suffix.slice(0, 8)}`, originId: lome.id, destinationId: brussels.id, method: 'SEA' }), 201);
      expectStatus(await req(`/warehouse/containers/${c.id}/parcels`, staff, 'POST', { trackingId: returnParcel.trackingId }), 201);
      for (const action of ['DEPARTED', 'ARRIVED']) expectStatus(await req(`/warehouse/containers/${c.id}/events`, staff, 'POST', { action }), 201);
      const p = expectStatus(await req(`/parcels/${returnParcel.id}`, staff), 200);
      assert.equal(p.status, 'ARRIVED_DESTINATION'); assert.equal(p.locationId, brussels.id);
      assert.ok(p.events.at(-1).note.includes('Brussels, Belgium'));
      for (const status of ['READY_FOR_PICKUP', 'DELIVERED']) expectStatus(await req(`/parcels/${p.id}/events`, staff, 'POST', { status }), 201);
    });
    await t.test('Marketplace products, orders, price snapshots and parcel linking are tenant-safe', async () => {
      const product = expectStatus(await req('/admin/commerce/products', admin, 'POST', { title: 'QA household item', category: 'Household', priceMinor: 1250, currency: 'USD' }), 201);
      const input = { kind: 'MARKETPLACE', customerId: profile.id, productId: product.id, quantity: 2 };
      expectStatus(await req('/admin/commerce/orders', admin, 'POST', input), 400);
      expectStatus(await req(`/admin/commerce/products/${product.id}`, admin, 'PATCH', { isActive: true }), 200);
      const order = expectStatus(await req('/admin/commerce/orders', admin, 'POST', input), 201);
      assert.equal(order.amountMinor, 2500);
      expectStatus(await req(`/admin/commerce/products/${product.id}`, admin, 'PATCH', { priceMinor: 2000 }), 200);
      const snapshot = expectStatus(await req('/admin/commerce/marketplace', admin), 200).orders.find(o => o.id === order.id);
      assert.equal(snapshot.amountMinor, 2500);
      expectStatus(await req(`/admin/commerce/orders/${order.id}`, foreignAdmin, 'PATCH', { status: 'ACCEPTED' }), 404);
      expectStatus(await req(`/admin/commerce/orders/${order.id}`, admin, 'PATCH', { amountMinor: 99 }), 409);
      for (const status of ['ACCEPTED', 'PROCESSING']) expectStatus(await req(`/admin/commerce/orders/${order.id}`, admin, 'PATCH', { status }), 200);
      expectStatus(await req(`/admin/commerce/orders/${order.id}`, admin, 'PATCH', { status: 'SHIPPED' }), 400);
      expectStatus(await req(`/admin/commerce/orders/${order.id}`, admin, 'PATCH', { status: 'SHIPPED', trackingId: outboundParcel.trackingId }), 200);
      expectStatus(await req(`/admin/commerce/orders/${order.id}`, admin, 'PATCH', { status: 'COMPLETED' }), 200);
      assert.equal(expectStatus(await req('/admin/commerce/marketplace', foreignAdmin), 200).orders.length, 0);
      expectStatus(await req('/admin/commerce/orders', admin, 'POST', { ...input, customerId: foreignProfile.id }), 404);
    });
    await t.test('Buy For Me requires a quote and acceptance before purchase; accepted amounts are locked', async () => {
      const order = expectStatus(await req('/admin/commerce/orders', admin, 'POST', { kind: 'BUY_FOR_ME', customerId: profile.id, title: 'QA purchase request', quantity: 1, sourceUrl: 'https://d2fshipping.com/shop/', currency: 'EUR' }), 201);
      expectStatus(await req('/admin/commerce/orders', admin, 'POST', { kind: 'BUY_FOR_ME', customerId: profile.id, title: 'Invalid source', sourceUrl: 'javascript:alert(1)' }), 400);
      const path = `/admin/commerce/orders/${order.id}`;
      expectStatus(await req(path, admin, 'PATCH', { status: 'PURCHASED' }), 409);
      expectStatus(await req(path, admin, 'PATCH', { status: 'QUOTED' }), 400);
      const quote = expectStatus(await req(path, admin, 'PATCH', { status: 'QUOTED', amountMinor: 15000 }), 200);
      assert.equal(quote.amountMinor, 15000);
      expectStatus(await req(path, admin, 'PATCH', { status: 'ACCEPTED' }), 200);
      expectStatus(await req(path, admin, 'PATCH', { amountMinor: 1 }), 409);
      for (const status of ['PURCHASED', 'RECEIVED']) expectStatus(await req(path, admin, 'PATCH', { status }), 200);
      expectStatus(await req(path, admin, 'PATCH', { status: 'SHIPPED', trackingId: returnParcel.trackingId }), 200);
      assert.ok(await prisma.auditLog.count({ where: { entityId: order.id, action: 'SERVICE_ORDER_UPDATE' } }) >= 5);
    });
  } finally {
    const ids = organizations.map(o => o.id), actorIds = users.map(u => u.id);
    const containers = await prisma.container.findMany({ where: { organizationId: { in: ids } }, select: { id: true } });
    await prisma.serviceOrder.deleteMany({ where: { organizationId: { in: ids } } });
    await prisma.product.deleteMany({ where: { organizationId: { in: ids } } });
    await prisma.trackingEvent.deleteMany({ where: { parcelId: { in: parcelIds } } });
    await prisma.trackingIndex.deleteMany({ where: { parcelId: { in: parcelIds } } });
    await prisma.parcel.deleteMany({ where: { organizationId: { in: ids } } });
    await prisma.containerEvent.deleteMany({ where: { containerId: { in: containers.map(c => c.id) } } });
    await prisma.container.deleteMany({ where: { organizationId: { in: ids } } });
    await prisma.auditLog.deleteMany({ where: { actorId: { in: actorIds } } });
    await prisma.customer.deleteMany({ where: { organizationId: { in: ids } } });
    await prisma.user.deleteMany({ where: { id: { in: actorIds } } });
    await prisma.location.deleteMany({ where: { organizationId: { in: ids } } });
    await prisma.organization.deleteMany({ where: { id: { in: ids } } });
    await new Promise(r => server.close(r)); await prisma.$disconnect();
  }
});
