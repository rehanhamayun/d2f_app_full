import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import app from '../src/app.js';
import { prisma } from '../src/db.js';
import { JWT_SECRET } from '../src/config.js';

test('admin dashboard analytics and user management require Admin access', async () => {
  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const suffix = randomUUID();
  const createdUserIds = [];
  const createdCustomerIds = [];
  const createdParcelIds = [];
  const createdEventIds = [];
  const createdAuditIds = [];
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
  const tokenFor = (user) =>
    jwt.sign(
      { id: user.id, purpose: 'session', ver: 0 },
      JWT_SECRET,
      { algorithm: 'HS256' },
    );

  try {
    const organization = await prisma.organization.findFirstOrThrow();
    const [admin, staff, customer] = await Promise.all([
      prisma.user.create({
        data: {
          email: `admin-${suffix}@example.com`,
          fullName: 'Dashboard Admin',
          passwordHash: await bcrypt.hash('dashboard-test-password', 4),
          role: 'ADMIN',
          organizationId: organization.id,
        },
      }),
      prisma.user.create({
        data: {
          email: `staff-${suffix}@example.com`,
          fullName: 'Dashboard Staff',
          passwordHash: 'unused',
          role: 'STAFF',
        },
      }),
      prisma.user.create({
        data: {
          email: `customer-${suffix}@example.com`,
          fullName: 'Dashboard Customer',
          passwordHash: 'unused',
          role: 'CUSTOMER',
        },
      }),
    ]);
    createdUserIds.push(admin.id, staff.id, customer.id);

    const customerProfile = await prisma.customer.create({
      data: {
        displayName: `Dashboard Test Customer ${suffix}`,
        email: customer.email,
      },
    });
    const secondCustomerProfile = await prisma.customer.create({
      data: {
        displayName: `Dashboard Test Customer Second ${suffix}`,
        email: `profile-${suffix}@example.com`,
      },
    });
    createdCustomerIds.push(customerProfile.id, secondCustomerProfile.id);
    const parcel = await prisma.parcel.create({
      data: {
        trackingId: `D2F-2099-${Math.floor(Math.random() * 900000 + 100000)}`,
        customerId: customerProfile.id,
        recipientName: `Dashboard Recipient ${suffix}`,
        packageType: 'BOX',
        weightKg: 1,
        origin: 'Omaha',
        destination: 'Lome',
        method: 'AIR',
        status: 'RECEIVED',
        createdById: staff.id,
      },
    });
    const secondParcel = await prisma.parcel.create({
      data: {
        trackingId: `D2F-2099-${Math.floor(Math.random() * 900000 + 100000)}`,
        customerId: secondCustomerProfile.id,
        recipientName: `Dashboard Recipient Second ${suffix}`,
        packageType: 'BOX',
        weightKg: 2,
        origin: 'Omaha',
        destination: 'Lome',
        method: 'SEA',
        status: 'IN_TRANSIT',
        createdById: staff.id,
      },
    });
    createdParcelIds.push(parcel.id, secondParcel.id);

    const event = await prisma.trackingEvent.create({
      data: { parcelId: parcel.id, status: 'RECEIVED', actorId: staff.id },
    });
    createdEventIds.push(event.id);
    const audit = await prisma.auditLog.create({
      data: {
        actorId: staff.id,
        action: 'ADMIN_DASHBOARD_TEST',
        entity: 'Parcel',
        entityId: parcel.id,
      },
    });
    createdAuditIds.push(audit.id);

    const adminToken = tokenFor(admin);
    const staffToken = tokenFor(staff);
    const customerToken = tokenFor(customer);
    assert.equal((await request('/admin/overview')).status, 401);
    assert.equal(
      (await request('/admin/overview', { token: staffToken })).status,
      403,
    );
    assert.equal(
      (await request('/admin/users', { token: customerToken })).status,
      403,
    );

    const overview = await request('/admin/overview?days=7', {
      token: adminToken,
    });
    assert.equal(overview.status, 200, JSON.stringify(overview.body));
    assert.equal(overview.body.periodDays, 7);
    assert.ok(overview.body.totalParcels >= 1);
    assert.ok(overview.body.customerCount >= 1);
    assert.equal(overview.body.parcelTrend.length, 7);
    assert.equal(overview.body.statusCounts.RECEIVED >= 1, true);
    assert.ok(
      overview.body.recentEvents.some(
        (item) => item.parcel.trackingId === parcel.trackingId,
      ),
    );
    assert.ok(
      overview.body.recentAudit.some((item) => item.id === audit.id),
    );
    assert.equal(
      (await request('/admin/overview?days=365', { token: adminToken }))
        .status,
      400,
    );

    const users = await request(`/admin/users?q=${suffix}`, {
      token: adminToken,
    });
    assert.equal(users.status, 200);
    assert.equal(users.body.total, 3);
    assert.equal(users.body.users.length, 3);
    assert.equal('passwordHash' in users.body.users[0], false);
    const nextUsersPage = await request(
      `/admin/users?q=${suffix}&limit=1&offset=1`,
      { token: adminToken },
    );
    assert.equal(nextUsersPage.status, 200);
    assert.equal(nextUsersPage.body.total, 3);
    assert.equal(nextUsersPage.body.users.length, 1);
    assert.equal(nextUsersPage.body.offset, 1);

    const parcelPage = await request(
      `/admin/parcels?q=${suffix}&limit=1&offset=0`,
      { token: adminToken },
    );
    assert.equal(parcelPage.status, 200, JSON.stringify(parcelPage.body));
    assert.equal(parcelPage.body.total, 2);
    assert.equal(parcelPage.body.parcels.length, 1);
    const nextParcelPage = await request(
      `/admin/parcels?q=${suffix}&limit=1&offset=1`,
      { token: adminToken },
    );
    assert.equal(nextParcelPage.status, 200);
    assert.equal(nextParcelPage.body.total, 2);
    assert.equal(nextParcelPage.body.parcels.length, 1);

    const customerPage = await request(
      `/admin/customers?q=${suffix}&limit=1&offset=0`,
      { token: adminToken },
    );
    assert.equal(customerPage.status, 200, JSON.stringify(customerPage.body));
    assert.equal(customerPage.body.total, 2);
    assert.equal(customerPage.body.customers.length, 1);
    const nextCustomerPage = await request(
      `/admin/customers?q=${suffix}&limit=1&offset=1`,
      { token: adminToken },
    );
    assert.equal(nextCustomerPage.status, 200);
    assert.equal(nextCustomerPage.body.total, 2);
    assert.equal(nextCustomerPage.body.customers.length, 1);
    assert.equal(
      (await request('/admin/customers?limit=101', { token: adminToken }))
        .status,
      400,
    );

    const deactivated = await request(`/admin/users/${staff.id}/active`, {
      token: adminToken,
      method: 'PATCH',
      data: { isActive: false },
    });
    assert.equal(deactivated.status, 200);
    assert.equal(deactivated.body.user.isActive, false);
    assert.equal(
      (await prisma.auditLog.findMany({
        where: {
          action: 'USER_DEACTIVATE',
          entityId: staff.id,
          actorId: admin.id,
        },
      })).length,
      1,
    );
    assert.equal(
      (
        await request(`/admin/users/${admin.id}/active`, {
          token: adminToken,
          method: 'PATCH',
          data: { isActive: false },
        })
      ).status,
      400,
    );
    assert.equal(
      (
        await request(`/admin/users/${customer.id}/active`, {
          token: customerToken,
          method: 'PATCH',
          data: { isActive: false },
        })
      ).status,
      403,
    );
  } finally {
    await prisma.auditLog.deleteMany({
      where: {
        OR: [
          { id: { in: createdAuditIds } },
          { entityId: { in: createdUserIds } },
          { entityId: { in: createdParcelIds } },
        ],
      },
    });
    await prisma.trackingEvent.deleteMany({
      where: {
        OR: [
          { id: { in: createdEventIds } },
          { parcelId: { in: createdParcelIds } },
        ],
      },
    });
    await prisma.trackingIndex.deleteMany({
      where: { parcelId: { in: createdParcelIds } },
    });
    await prisma.parcel.deleteMany({
      where: { id: { in: createdParcelIds } },
    });
    await prisma.customer.deleteMany({
      where: { id: { in: createdCustomerIds } },
    });
    await prisma.user.deleteMany({ where: { id: { in: createdUserIds } } });
    await new Promise((resolve) => server.close(resolve));
    await prisma.$disconnect();
  }
});
