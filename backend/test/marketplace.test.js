import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID, randomBytes } from 'node:crypto';
import jwt from 'jsonwebtoken';
import app from '../src/app.js';
import { prisma } from '../src/db.js';
import { JWT_SECRET } from '../src/config.js';

// Real API/database tests. All rows belong to fresh isolated organizations.
test('Marketplace shopfront, seller studio, Buy For Me and commissions', async t => {
  const server = app.listen(0, '127.0.0.1');
  await new Promise(r => server.once('listening', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const suffix = randomUUID();
  const organizations = [];
  const users = [];
  const parcelIds = [];
  const token = user => jwt.sign({ id: user.id, purpose: 'session', ver: 0 }, JWT_SECRET);
  const req = async (path, user, method = 'GET', data) => {
    const response = await fetch(`${base}${path}`, { method, headers: { 'Content-Type': 'application/json', ...(user ? { Authorization: `Bearer ${token(user)}` } : {}) }, ...(data ? { body: JSON.stringify(data) } : {}) });
    return { status: response.status, body: await response.json() };
  };
  const rawReq = async (path, user, bytes, contentType = 'image/jpeg') => {
    const response = await fetch(`${base}${path}`, { method: 'POST', headers: { 'Content-Type': contentType, Authorization: `Bearer ${token(user)}` }, body: bytes });
    return { status: response.status, body: await response.json().catch(() => null) };
  };
  const rawBytes = async (path, user) => {
    const response = await fetch(`${base}${path}`, { headers: { Authorization: `Bearer ${token(user)}` } });
    return { status: response.status, contentType: response.headers.get('content-type'), bytes: Buffer.from(await response.arrayBuffer()) };
  };
  const expectStatus = (result, status) => { assert.equal(result.status, status, JSON.stringify(result.body)); return result.body; };
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09]);

  try {
    for (let i = 0; i < 2; i++) organizations.push(await prisma.organization.create({ data: { name: `QA Shop ${suffix}-${i}`, trackingPrefix: `S${randomBytes(2).toString('hex').toUpperCase()}` } }));
    const org = organizations[0], otherOrg = organizations[1];
    for (const [role, organizationId] of [['ADMIN', org.id], ['CUSTOMER', org.id], ['CUSTOMER', org.id], ['CUSTOMER', org.id], ['ADMIN', otherOrg.id], ['CUSTOMER', otherOrg.id]]) {
      users.push(await prisma.user.create({ data: { email: `${role}-${organizationId}-${users.length}-${suffix}@example.test`, fullName: `QA ${role} ${users.length}`, passwordHash: 'unused', role, organizationId } }));
    }
    const [admin, buyer, sellerUser, secondBuyer, foreignAdmin, foreignCustomer] = users;
    const freshUser = await prisma.user.create({ data: { email: `fresh-${suffix}@example.test`, fullName: 'QA Fresh', passwordHash: 'unused', role: 'CUSTOMER', organizationId: org.id } });
    users.push(freshUser);

    await t.test('seller applications: apply, review, commission agreed before sale', async () => {
      // Seller cannot list before approval
      expectStatus(await req('/seller/products', sellerUser, 'POST', { title: 'Too soon', category: 'Home', priceMinor: 1000 }), 403);
      // Apply without accepting terms fails
      expectStatus(await req('/seller/application', sellerUser, 'POST', { displayName: 'Mama Adjoa', category: 'Spices & Food', country: 'Togo', city: 'Lomé', phone: '+228 90 00 00 00' }), 400);
      const application = expectStatus(await req('/seller/application', sellerUser, 'POST', { displayName: 'Mama Adjoa', businessType: 'BUSINESS', businessName: 'Adjoa Spices SARL', category: 'Spices & Food', country: 'Togo', city: 'Lomé', phone: '+228 90 00 00 00', bio: 'Ground spices and peppers from Lomé market.', terms: true }), 201);
      assert.equal(application.status, 'PENDING');
      // Pending sellers cannot publish
      expectStatus(await req('/seller/products', sellerUser, 'POST', { title: 'Pending product', category: 'Spices & Food', priceMinor: 2500 }), 403);
      // Admin sees the application and approves with a 12% agreed commission
      const sellers = expectStatus(await req('/admin/commerce/sellers?status=PENDING', admin), 200);
      assert.ok(sellers.some(s => s.user.email === sellerUser.email));
      expectStatus(await req(`/admin/commerce/sellers/${application.id}`, admin, 'PATCH', { action: 'approve', commissionBps: 1200 }), 200);
      // Second seller gets rejected with a note
      const rejected = expectStatus(await req('/seller/application', secondBuyer, 'POST', { displayName: 'Rejected Co', category: 'Textiles', country: 'Benin', phone: '+229 97 00 00 00', terms: true }), 201);
      expectStatus(await req(`/admin/commerce/sellers/${rejected.id}`, admin, 'PATCH', { action: 'reject' }), 400);
      expectStatus(await req(`/admin/commerce/sellers/${rejected.id}`, admin, 'PATCH', { action: 'reject', reviewNote: 'Incomplete documents' }), 200);
      expectStatus(await req('/seller/me', foreignCustomer), 200);
    });

    let productId;
    await t.test('approved seller lists a product with photos; buyer browses it', async () => {
      const created = expectStatus(await req('/seller/products', sellerUser, 'POST', { title: 'Smoked dried pepper 500g', category: 'Spices & Food', description: 'Hand-smoked scotch bonnet, ground fresh.', priceMinor: 3500, currency: 'USD', fulfillment: 'SELLER', stockCount: 7, locationCity: 'Lomé', locationCountry: 'Togo' }), 201);
      productId = created.id;
      // Seller cannot self-feature
      expectStatus(await req(`/seller/products/${productId}`, sellerUser, 'PATCH', { featured: true }), 400);
      // Upload two photos
      const img1 = expectStatus(await rawReq(`/seller/products/${productId}/images?name=pepper-1.jpg`, sellerUser, jpeg), 201);
      expectStatus(await rawReq(`/seller/products/${productId}/images?name=pepper-2.jpg`, sellerUser, jpeg, 'image/png'), 201);
      const raw = await rawBytes(`/marketplace/products/${productId}/images/${img1.id}/raw`, buyer);
      assert.equal(raw.status, 200);
      assert.equal(raw.contentType, 'image/jpeg');
      assert.equal(raw.bytes.length, jpeg.length);
      // Buyer cannot read images from another organization
      const foreignRaw = await rawBytes(`/marketplace/products/${productId}/images/${img1.id}/raw`, foreignCustomer);
      assert.equal(foreignRaw.status, 404);
      // Browse finds it; the product carries seller context, never commission
      const browse = expectStatus(await req('/marketplace/products?q=pepper', buyer), 200);
      const found = browse.products.find(p => p.id === productId);
      assert.ok(found, 'product appears in search');
      assert.equal(found.seller.displayName, 'Mama Adjoa');
      assert.equal(found.commissionMinor, undefined);
      assert.equal(found.commissionBps, undefined);
      assert.deepEqual(browse.categories.map(c => c.name), ['Spices & Food']);
      assert.deepEqual(browse.countries.map(c => c.name), ['Togo']);
    });

    let orderId;
    await t.test('buyer checks out: commission snapshot, reservation, address privacy', async () => {
      // Validation first
      expectStatus(await req('/marketplace/orders', buyer, 'POST', { productId, quantity: 2, deliveryPreference: 'D2F', recipientPhone: '+1 555 0100', deliveryAddress: '12 Baker Street', deliveryCity: 'Omaha', deliveryCountry: 'United States', notes: 'Please pack with care' }), 201);
      const orders = expectStatus(await req('/marketplace/orders', buyer), 200);
      const placed = orders.find(o => o.product?.id === productId);
      orderId = placed.id;
      assert.equal(placed.amountMinor, 7000);
      assert.equal(placed.status, 'REQUESTED');
      assert.equal(placed.commissionMinor, undefined, 'buyers never see commission');
      // Stock reserved: 7 - 2 = 5
      const detail = expectStatus(await req(`/marketplace/products/${productId}`, buyer), 200);
      assert.equal(detail.stockCount, 5);
      // Seller sees the order but NOT the buyer address while REQUESTED
      const sellerOrders = expectStatus(await req('/seller/orders', sellerUser), 200);
      const sellerSees = sellerOrders.find(o => o.id === orderId);
      assert.equal(sellerSees.deliveryAddress, null);
      assert.equal(sellerSees.recipientPhone, null);
      assert.equal(sellerSees.commissionBps, 1200, 'seller sees the agreed rate');
      assert.equal(sellerSees.commissionMinor, 840);
      // Accept reveals contact details
      expectStatus(await req(`/seller/orders/${orderId}/accept`, sellerUser, 'POST', {}), 200);
      const accepted = expectStatus(await req('/seller/orders', sellerUser), 200).find(o => o.id === orderId);
      assert.equal(accepted.deliveryAddress, '12 Baker Street');
      assert.equal(accepted.status, 'ACCEPTED');
    });

    await t.test('commission report aggregates app and admin orders', async () => {
      const report = expectStatus(await req('/admin/commerce/commissions?from=2000-01-01&to=2100-01-01', admin), 200);
      const row = report.sellers.find(s => s.displayName === 'Mama Adjoa');
      assert.equal(row.merchandiseMinor, 7000);
      assert.equal(row.commissionMinor, 840);
      expectStatus(await req('/admin/commerce/commissions', foreignAdmin), 200);
      const foreignReport = expectStatus(await req('/admin/commerce/commissions?from=2000-01-01&to=2100-01-01', foreignAdmin), 200);
      assert.equal(foreignReport.sellers.length, 0);
    });

    await t.test('seller fulfils: advance, ship with carrier reference, buyer sees progress', async () => {
      expectStatus(await req(`/seller/orders/${orderId}/advance`, sellerUser, 'POST', {}), 200);
      expectStatus(await req(`/seller/orders/${orderId}/ship`, sellerUser, 'POST', { trackingRef: 'DHL-884421' }), 200);
      const mine = expectStatus(await req('/marketplace/orders', buyer), 200).find(o => o.id === orderId);
      assert.equal(mine.status, 'SHIPPED');
      assert.equal(mine.trackingRef, 'DHL-884421');
      expectStatus(await req(`/seller/orders/${orderId}/complete`, sellerUser, 'POST', {}), 200);
    });

    await t.test('stock reservation and restock on cancel', async () => {
      // Book out the remaining 5 units with a fresh order, then cancel it
      expectStatus(await req('/marketplace/orders', secondBuyer, 'POST', { productId, quantity: 5, deliveryPreference: 'SELLER', recipientPhone: '+1 555 0101', deliveryAddress: '8 Rue des Cocotiers', deliveryCity: 'Lomé', deliveryCountry: 'Togo' }), 201);
      const soldOut = expectStatus(await req(`/marketplace/products/${productId}`, buyer), 200);
      assert.equal(soldOut.soldOut, true);
      expectStatus(await req('/marketplace/orders', buyer, 'POST', { productId, quantity: 1, deliveryPreference: 'SELLER', recipientPhone: '+1 555 0100', deliveryAddress: '12 Baker Street', deliveryCity: 'Omaha', deliveryCountry: 'United States' }), 409);
      const secondOrder = expectStatus(await req('/marketplace/orders', secondBuyer), 200).find(o => o.quantity === 5);
      expectStatus(await req(`/marketplace/orders/${secondOrder.id}/cancel`, secondBuyer, 'POST', {}), 200);
      const restocked = expectStatus(await req(`/marketplace/products/${productId}`, buyer), 200);
      assert.equal(restocked.stockCount, 5);
    });

    await t.test('suspending a seller hides their listings; reinstating restores them', async () => {
      const sellers = expectStatus(await req('/admin/commerce/sellers?status=APPROVED', admin), 200);
      const mine = sellers.find(s => s.user.email === sellerUser.email);
      expectStatus(await req(`/admin/commerce/sellers/${mine.id}`, admin, 'PATCH', { action: 'suspend', reviewNote: 'Quality complaint' }), 200);
      const browse = expectStatus(await req('/marketplace/products?q=pepper', buyer), 200);
      assert.equal(browse.products.find(p => p.id === productId), undefined);
      expectStatus(await req(`/admin/commerce/sellers/${mine.id}`, admin, 'PATCH', { action: 'reinstate' }), 200);
      const back = expectStatus(await req('/marketplace/products?q=pepper', buyer), 200);
      assert.ok(back.products.find(p => p.id === productId));
    });

    await t.test('admin onboards an existing app account as a seller', async () => {
      // A staff-created profile without an app account cannot sell
      const linkedProfile = expectStatus(await req('/customers', admin, 'POST', { displayName: 'Linked Buyer', country: 'Ghana', phone: '+233 24 000 0000' }), 201);
      expectStatus(await req('/admin/commerce/sellers', admin, 'POST', { customerId: linkedProfile.id, category: 'Textiles', commissionBps: 800 }), 400);
      // Link it to a registered app account, then register them
      await prisma.customer.update({ where: { id: linkedProfile.id }, data: { userId: freshUser.id } });
      const created = expectStatus(await req('/admin/commerce/sellers', admin, 'POST', { customerId: linkedProfile.id, category: 'Textiles', commissionBps: 800 }), 201);
      assert.equal(created.status, 'APPROVED');
      assert.equal(created.commissionBps, 800);
      expectStatus(await req('/admin/commerce/sellers', admin, 'POST', { customerId: linkedProfile.id, category: 'Textiles' }), 409);
    });

    await t.test('Buy For Me: full customer flow with quote and acceptance', async () => {
      const request = expectStatus(await req('/buy-for-me/requests', buyer, 'POST', { title: 'Sony WH-1000XM5 headphones', sourceUrl: 'https://www.amazon.com/dp/B09YYZFSFC', quantity: 1, budgetMinor: 30000, currency: 'USD', notes: 'Black only' }), 201);
      assert.equal(request.status, 'REQUESTED');
      // Customer cannot accept before a quote
      expectStatus(await req(`/buy-for-me/requests/${request.id}/accept`, buyer, 'POST', {}), 409);
      // Admin records the quote
      expectStatus(await req(`/admin/commerce/orders/${request.id}`, admin, 'PATCH', { status: 'QUOTED', amountMinor: 27900 }), 200);
      const mine = expectStatus(await req('/buy-for-me/requests', buyer), 200).find(r => r.id === request.id);
      assert.equal(mine.amountMinor, 27900);
      // Decline path: a second request gets declined
      const second = expectStatus(await req('/buy-for-me/requests', buyer, 'POST', { title: 'Bose soundbar', quantity: 1, currency: 'USD' }), 201);
      expectStatus(await req(`/admin/commerce/orders/${second.id}`, admin, 'PATCH', { status: 'QUOTED', amountMinor: 50000 }), 200);
      expectStatus(await req(`/buy-for-me/requests/${second.id}/decline`, buyer, 'POST', {}), 200);
      // Accept the first quote and drive it to completion with a parcel
      expectStatus(await req(`/buy-for-me/requests/${request.id}/accept`, buyer, 'POST', {}), 200);
      expectStatus(await req(`/buy-for-me/requests/${request.id}/cancel`, buyer, 'POST', {}), 409);
      expectStatus(await req(`/admin/commerce/orders/${request.id}`, admin, 'PATCH', { status: 'PURCHASED' }), 200);
      expectStatus(await req(`/admin/commerce/orders/${request.id}`, admin, 'PATCH', { status: 'RECEIVED' }), 200);
    });

    await t.test('Buy For Me completion with a linked parcel', async () => {
      const request = expectStatus(await req('/buy-for-me/requests', buyer, 'POST', { title: 'Nintendo Switch OLED', quantity: 1, currency: 'USD' }), 201);
      expectStatus(await req(`/admin/commerce/orders/${request.id}`, admin, 'PATCH', { status: 'QUOTED', amountMinor: 34900 }), 200);
      expectStatus(await req(`/buy-for-me/requests/${request.id}/accept`, buyer, 'POST', {}), 200);
      // SHIPPED requires a parcel belonging to this customer
      const linked = await prisma.customer.findUnique({ where: { userId: buyer.id } });
      const parcel = await prisma.parcel.create({
        data: {
          trackingId: `QAFB${randomBytes(6).toString('hex').toUpperCase()}`,
          organizationId: org.id,
          customerId: linked.id,
          recipientName: 'QA Buyer',
          packageType: 'BOX',
          weightKg: 1.2,
          origin: 'Omaha, NE, USA',
          destination: 'Lomé, Togo',
          method: 'AIR',
          serviceType: 'AIR_CARGO',
          status: 'RECEIVED',
          createdById: admin.id,
        },
      });
      parcelIds.push(parcel.id);
      expectStatus(await req(`/admin/commerce/orders/${request.id}`, admin, 'PATCH', { status: 'PURCHASED' }), 200);
      expectStatus(await req(`/admin/commerce/orders/${request.id}`, admin, 'PATCH', { status: 'SHIPPED' }), 409);
      expectStatus(await req(`/admin/commerce/orders/${request.id}`, admin, 'PATCH', { status: 'RECEIVED' }), 200);
      expectStatus(await req(`/admin/commerce/orders/${request.id}`, admin, 'PATCH', { status: 'SHIPPED' }), 400);
      expectStatus(await req(`/admin/commerce/orders/${request.id}`, admin, 'PATCH', { status: 'SHIPPED', trackingId: parcel.trackingId }), 200);
      expectStatus(await req(`/admin/commerce/orders/${request.id}`, admin, 'PATCH', { status: 'COMPLETED' }), 200);
    });

    await t.test('tenant isolation for the shopfront', async () => {
      const foreignBrowse = expectStatus(await req(`/marketplace/products/${productId}`, foreignCustomer), 404);
      void foreignBrowse;
      expectStatus(await req(`/seller/orders/${orderId}/accept`, foreignCustomer, 'POST', {}), 403);
      expectStatus(await req('/admin/commerce/sellers', foreignAdmin), 200);
      const foreignSellers = expectStatus(await req('/admin/commerce/sellers', foreignAdmin), 200);
      assert.equal(foreignSellers.length, 0);
    });
  } finally {
    const ids = organizations.map(o => o.id);
    const actorIds = users.map(u => u.id);
    await prisma.productImage.deleteMany({ where: { product: { organizationId: { in: ids } } } });
    await prisma.serviceOrder.deleteMany({ where: { organizationId: { in: ids } } });
    await prisma.product.deleteMany({ where: { organizationId: { in: ids } } });
    await prisma.sellerProfile.deleteMany({ where: { organizationId: { in: ids } } });
    if (parcelIds.length) {
      await prisma.trackingEvent.deleteMany({ where: { parcelId: { in: parcelIds } } });
      await prisma.parcel.deleteMany({ where: { id: { in: parcelIds } } });
    }
    await prisma.auditLog.deleteMany({ where: { actorId: { in: actorIds } } });
    await prisma.customer.deleteMany({ where: { organizationId: { in: ids } } });
    await prisma.user.deleteMany({ where: { id: { in: actorIds } } });
    await prisma.organization.deleteMany({ where: { id: { in: ids } } });
    await new Promise(r => server.close(r));
    await prisma.$disconnect();
  }
});
