import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import jwt from 'jsonwebtoken';
import app from '../src/app.js';
import { prisma } from '../src/db.js';
import { JWT_SECRET } from '../src/config.js';

test('customer parcel requests are linked to and isolated by the signed-in customer', async () => {
  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const suffix = randomUUID();
  const createdUsers = [];
  const createdParcels = [];
  const request = async (path, { token, method = 'GET', data } = {}) => {
    const response = await fetch(`${base}${path}`, {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      ...(data ? { body: JSON.stringify(data) } : {}),
    });
    return { status: response.status, body: await response.json() };
  };

  try {
    const organization = await prisma.organization.findFirstOrThrow();
    const omaha = await prisma.location.findFirstOrThrow({
      where: { organizationId: organization.id, code: 'OMA-1' },
    });
    const customer = await prisma.user.create({
      data: {
        email: `customer-${suffix}@example.com`,
        fullName: 'Self Service Customer',
        phone: '+22890123456',
        passwordHash: 'unused',
        role: 'CUSTOMER',
        organizationId: organization.id,
      },
    });
    createdUsers.push(customer.id);
    const otherCustomer = await prisma.user.create({
      data: {
        email: `other-${suffix}@example.com`,
        fullName: 'Other Customer',
        passwordHash: 'unused',
        role: 'CUSTOMER',
        organizationId: organization.id,
      },
    });
    createdUsers.push(otherCustomer.id);
    const staff = await prisma.user.create({
      data: {
        email: `staff-${suffix}@example.com`,
        fullName: 'Customer Parcel Test Staff',
        passwordHash: 'unused',
        role: 'STAFF',
        organizationId: organization.id,
        locationId: omaha.id,
      },
    });
    createdUsers.push(staff.id);

    const tokenFor = (user) =>
      jwt.sign(
        { id: user.id, purpose: 'session', ver: 0 },
        JWT_SECRET,
        { algorithm: 'HS256' },
      );
    const customerToken = tokenFor(customer);
    const otherCustomerToken = tokenFor(otherCustomer);
    const staffToken = tokenFor(staff);
    const input = {
      recipientName: 'Test Recipient',
      recipientPhone: '+22890000000',
      recipientAddress: 'Lomé, Togo',
      packageType: 'BOX',
      weightKg: 2.5,
      origin: 'Omaha, NE, USA',
      destination: 'Lomé, Togo',
      method: 'AIR',
      clientRequestId: `customer-${suffix}`,
    };

    assert.equal((await request('/customer/parcels')).status, 401);
    assert.equal(
      (await request('/customer/parcels', { token: staffToken })).status,
      403,
    );
    assert.equal(
      (await request('/customer/parcels', { token: customerToken })).body
        .length,
      0,
    );
    assert.equal(
      (
        await request('/customer/parcels', {
          token: customerToken,
          method: 'POST',
          data: { ...input, packageType: 'INVALID' },
        })
      ).status,
      400,
    );
    assert.equal(
      (
        await request('/parcels', {
          token: customerToken,
          method: 'POST',
          data: { customerId: 'attacker-selected', ...input },
        })
      ).status,
      403,
    );

    const created = await request('/customer/parcels', {
      token: customerToken,
      method: 'POST',
      data: { ...input, customerId: 'attacker-selected' },
    });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    createdParcels.push(created.body.id);
    assert.match(created.body.trackingId, /^D2F\d{12}$/);
    assert.equal(created.body.status, 'REQUESTED');
    assert.equal(created.body.events.length, 1);
    assert.equal(created.body.events[0].status, 'REQUESTED');

    const linkedCustomer = await prisma.customer.findUniqueOrThrow({
      where: { userId: customer.id },
    });
    assert.equal(created.body.customerId, linkedCustomer.id);
    assert.equal(linkedCustomer.displayName, customer.fullName);
    assert.equal(linkedCustomer.email, customer.email);
    assert.equal(linkedCustomer.phone, customer.phone);
    assert.equal(linkedCustomer.organizationId, customer.organizationId);
    const savedParcel = await prisma.parcel.findUniqueOrThrow({
      where: { id: created.body.id },
      select: { trackingSequence: true },
    });
    assert.ok(
      created.body.trackingId.endsWith(
        savedParcel.trackingSequence.toString().padStart(12, '0'),
      ),
    );

    const ownParcels = await request('/customer/parcels', {
      token: customerToken,
    });
    assert.equal(ownParcels.status, 200);
    assert.equal(ownParcels.body.length, 1);
    assert.equal(ownParcels.body[0].trackingId, created.body.trackingId);
    assert.equal(
      (
        await request('/customer/parcels', {
          token: otherCustomerToken,
        })
      ).body.length,
      0,
    );
    const stolenRequestId = await request('/customer/parcels', {
      token: otherCustomerToken,
      method: 'POST',
      data: input,
    });
    assert.equal(stolenRequestId.status, 409);

    const retried = await request('/customer/parcels', {
      token: customerToken,
      method: 'POST',
      data: input,
    });
    assert.equal(retried.status, 200);
    assert.equal(retried.body.id, created.body.id);

    const staffTransition = await request(
      `/parcels/${created.body.id}/events`,
      {
        token: staffToken,
        method: 'POST',
        data: { status: 'RECEIVED', locationId: omaha.id, confirmed: true },
      },
    );
    assert.equal(staffTransition.status, 201, JSON.stringify(staffTransition.body));
  } finally {
    await prisma.auditLog.deleteMany({
      where: { entityId: { in: createdParcels } },
    });
    await prisma.trackingEvent.deleteMany({
      where: { parcelId: { in: createdParcels } },
    });
    await prisma.trackingIndex.deleteMany({
      where: { parcelId: { in: createdParcels } },
    });
    await prisma.parcel.deleteMany({
      where: { id: { in: createdParcels } },
    });
    await prisma.customer.deleteMany({
      where: { userId: { in: createdUsers } },
    });
    await prisma.user.deleteMany({ where: { id: { in: createdUsers } } });
    await new Promise((resolve) => server.close(resolve));
    await prisma.$disconnect();
  }
});
