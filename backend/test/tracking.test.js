import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import jwt from 'jsonwebtoken';
import app from '../src/app.js';
import { JWT_SECRET } from '../src/config.js';
import { prisma } from '../src/db.js';
import { generateTrackingId } from '../src/tracking.js';

function testPrefix() {
  return randomUUID()
    .replaceAll('-', '')
    .slice(0, 5)
    .replace(/[0-9a-f]/g, (digit) => String.fromCharCode(65 + Number.parseInt(digit, 16)));
}

test('organization tracking allocation is isolated, concurrent-safe, and permanent', async (t) => {
  const suffix = randomUUID();
  const organizations = [];
  const users = [];
  const customers = [];
  const parcels = [];

  try {
    const [first, second] = await Promise.all([
      prisma.organization.create({
        data: { name: `Tracking First ${suffix}`, trackingPrefix: testPrefix().toLowerCase() },
      }),
      prisma.organization.create({
        data: { name: `Tracking Second ${suffix}`, trackingPrefix: testPrefix() },
      }),
    ]);
    organizations.push(first.id, second.id);
    await t.test('prefixes are normalized, unique, and reserved on creation', async () => {
      assert.match(first.trackingPrefix, /^[A-Z0-9]{3,5}$/);
      await assert.rejects(prisma.organization.create({
        data: { name: 'Duplicate prefix fixture', trackingPrefix: first.trackingPrefix.toLowerCase() },
      }));
      const existing = await prisma.organization.upsert({
        where: { id: first.id }, update: {},
        create: { id: first.id, name: first.name, trackingPrefix: first.trackingPrefix },
      });
      assert.equal(existing.id, first.id);
    });
    await assert.rejects(
      prisma.organization.update({
        where: { id: first.id },
        data: { trackingPrefix: second.trackingPrefix },
      }),
      /Organization tracking prefixes are permanent/,
    );

    for (const organization of [first, second]) {
      const user = await prisma.user.create({
        data: {
          email: `tracking-${organization.id}@example.com`,
          fullName: 'Tracking test staff',
          passwordHash: 'unused',
          role: 'STAFF',
          organizationId: organization.id,
        },
      });
      const customer = await prisma.customer.create({
        data: {
          displayName: 'Tracking test customer',
          organizationId: organization.id,
        },
      });
      users.push(user.id);
      customers.push(customer.id);
    }

    async function createParcel(organization, index) {
      return prisma.$transaction(async (tx) => {
        const tracking = await generateTrackingId(tx, organization.id);
        const parcel = await tx.parcel.create({
          data: {
            ...tracking,
            customerId: customers[organizations.indexOf(organization.id)],
            recipientName: `Tracking Recipient ${index}`,
            packageType: 'BOX',
            weightKg: 1,
            origin: 'Origin',
            destination: 'Destination',
            createdById: users[organizations.indexOf(organization.id)],
          },
          select: {
            id: true,
            trackingId: true,
            trackingSequence: true,
            organizationId: true,
          },
        });
        return parcel;
      });
    }

    const created = await Promise.all(
      [first, second].flatMap((organization) =>
        Array.from({ length: 8 }, (_, index) =>
          createParcel(organization, index),
        ),
      ),
    );
    parcels.push(...created.map((parcel) => parcel.id));

    for (const organization of [first, second]) {
      const rows = created
        .filter((parcel) => parcel.organizationId === organization.id)
        .sort((a, b) => Number(a.trackingSequence - b.trackingSequence));
      assert.equal(rows.length, 8);
      assert.deepEqual(
        rows.map((parcel) => parcel.trackingSequence),
        Array.from({ length: 8 }, (_, index) => BigInt(index + 1)),
      );
      assert.equal(new Set(rows.map((parcel) => parcel.trackingId)).size, 8);
      assert.ok(
        rows.every((parcel) =>
          new RegExp(`^${organization.trackingPrefix}\\d{12}$`).test(parcel.trackingId),
        ),
      );
      assert.ok(
        rows.every((parcel) =>
          parcel.trackingId.endsWith(
            parcel.trackingSequence.toString().padStart(12, '0'),
          ),
        ),
      );
    }
    assert.equal(new Set(created.map((parcel) => parcel.trackingId)).size, 16);
    assert.equal(new Set(created.map((parcel) => parcel.id)).size, 16);
    assert.ok(created.every((parcel) => /^[\da-f]{8}-(?:[\da-f]{4}-){3}[\da-f]{12}$/i.test(parcel.id)));

    await t.test('parcel identities and allocated counters cannot be rewritten', async () => {
      const parcel = created[0];
      for (const data of [
        { id: randomUUID() }, { trackingId: 'REWRITTEN' },
        { trackingSequence: 90n }, { organizationId: second.id },
      ]) {
        await assert.rejects(prisma.parcel.update({ where: { id: parcel.id }, data }),
          /Parcel tracking identities are permanent/);
      }
      await assert.rejects(prisma.organization.update({
        where: { id: first.id }, data: { trackingCounter: 1n },
      }), /Tracking counters cannot move backwards/);
    });

    const deleted = created[0];

    await prisma.parcel.deleteMany({ where: { id: { in: parcels } } });
    parcels.length = 0;
    const next = await createParcel(first, 99);
    parcels.push(next.id);
    assert.equal(next.trackingSequence, 9n);

    await t.test('deleted parcel numbers and UUIDs remain permanently reserved', async () => {
      const data = {
        organizationId: deleted.organizationId,
        customerId: customers[organizations.indexOf(deleted.organizationId)],
        createdById: users[organizations.indexOf(deleted.organizationId)],
        recipientName: 'Deleted identity test', packageType: 'BOX', weightKg: 1,
        origin: 'Origin', destination: 'Destination',
      };
      await assert.rejects(prisma.parcel.create({ data: {
        ...data, trackingId: deleted.trackingId, trackingSequence: deleted.trackingSequence,
      } }));
      await assert.rejects(prisma.parcel.create({ data: {
        ...data, id: deleted.id, trackingId: `LEGACY-${suffix}`,
      } }));
      const reservation = await prisma.trackingNumberReservation.findUniqueOrThrow({
        where: { parcelId: deleted.id },
      });
      assert.equal(reservation.trackingId, deleted.trackingId);
      await assert.rejects(prisma.trackingNumberReservation.delete({
        where: { parcelId: deleted.id },
      }), /Tracking reservations are permanent/);
    });

    await t.test('failed creations do not publish or consume an identity', async () => {
      const before = await prisma.organization.findUniqueOrThrow({ where: { id: first.id } });
      await assert.rejects(prisma.$transaction(async tx => {
        await generateTrackingId(tx, first.id);
        throw new Error('Synthetic transaction failure');
      }));
      const after = await prisma.organization.findUniqueOrThrow({ where: { id: first.id } });
      assert.equal(after.trackingCounter, before.trackingCounter);
    });

    await t.test('exhaustion fails explicitly and inactive organizations cannot allocate', async () => {
      await prisma.organization.update({ where: { id: second.id }, data: { trackingCounter: 1000000000000n } });
      await assert.rejects(prisma.$transaction(tx => generateTrackingId(tx, second.id)), /exhausted/);
      await prisma.organization.update({ where: { id: first.id }, data: { isActive: false } });
      await assert.rejects(prisma.$transaction(tx => generateTrackingId(tx, first.id)), /missing or inactive/);
    });

    await prisma.parcel.deleteMany({ where: { id: { in: parcels } } });
    parcels.length = 0;
    await prisma.customer.deleteMany({ where: { id: { in: customers } } });
    customers.length = 0;
    await prisma.user.deleteMany({ where: { id: { in: users } } });
    users.length = 0;
    await prisma.organization.delete({ where: { id: first.id } });
    await t.test('a retired/deleted organization never frees its prefix', async () => {
      await assert.rejects(prisma.organization.create({
        data: { name: 'Recycled prefix fixture', trackingPrefix: first.trackingPrefix },
      }));
      await assert.rejects(prisma.organization.create({
        data: { id: first.id, name: 'Recycled identity fixture', trackingPrefix: first.trackingPrefix },
      }));
    });
  } finally {
    await prisma.parcel.deleteMany({ where: { id: { in: parcels } } });
    await prisma.customer.deleteMany({ where: { id: { in: customers } } });
    await prisma.user.deleteMany({ where: { id: { in: users } } });
    await prisma.organization.deleteMany({ where: { id: { in: organizations } } });
    await prisma.$disconnect();
  }
});

test('organizations can concurrently retry the same request key without sharing parcels', async () => {
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const organizations = [], users = [], customers = [], parcels = [];
  const requestKey = `shared-retry-${randomUUID()}`;
  const fixtures = [];
  const request = async (path, token, data) => {
    const response = await fetch(base + path, {
      method: data ? 'POST' : 'GET',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      ...(data ? { body: JSON.stringify(data) } : {}),
    });
    return { status: response.status, body: await response.json() };
  };
  try {
    for (let i = 0; i < 2; i++) {
      const organization = await prisma.organization.create({
        data: { name: `Retry organization ${requestKey} ${i}`, trackingPrefix: testPrefix() },
      });
      organizations.push(organization.id);
      const user = await prisma.user.create({ data: {
        email: `retry-${organization.id}@example.com`, fullName: 'Retry fixture',
        passwordHash: 'unused', role: 'STAFF', organizationId: organization.id,
      } });
      users.push(user.id);
      const customer = await prisma.customer.create({ data: {
        displayName: 'Retry customer', organizationId: organization.id,
      } });
      customers.push(customer.id);
      const token = jwt.sign({ id: user.id, purpose: 'session', ver: 0 }, JWT_SECRET);
      fixtures.push({ organization, customer, token });
    }
    const responses = await Promise.all(fixtures.flatMap(fixture =>
      Array.from({ length: 3 }, () => request('/parcels', fixture.token, {
        customerId: fixture.customer.id, recipientName: 'Retry recipient',
        packageType: 'BOX', weightKg: 1, origin: 'Origin', destination: 'Destination',
        clientRequestId: requestKey,
      })),
    ));
    parcels.push(...new Set(responses.map(result => result.body.id).filter(Boolean)));
    assert.ok(responses.every(result => [200, 201].includes(result.status)), JSON.stringify(responses));
    assert.equal(parcels.length, 2);
    for (let i = 0; i < fixtures.length; i++) {
      const own = responses.slice(i * 3, (i + 1) * 3);
      assert.equal(new Set(own.map(result => result.body.id)).size, 1);
      assert.equal(own.filter(result => result.status === 201).length, 1);
      assert.equal(own[0].body.trackingId, fixtures[i].organization.trackingPrefix + '000000000001');
      const foreignId = responses[(1 - i) * 3].body.id;
      assert.equal((await request('/parcels/' + foreignId, fixtures[i].token)).status, 404);
      const list = await request('/parcels', fixtures[i].token);
      assert.equal(list.body.length, 1);
      assert.equal(list.body[0].organizationId, fixtures[i].organization.id);
    }
  } finally {
    await prisma.auditLog.deleteMany({ where: { entityId: { in: parcels } } });
    await prisma.trackingEvent.deleteMany({ where: { parcelId: { in: parcels } } });
    await prisma.trackingIndex.deleteMany({ where: { parcelId: { in: parcels } } });
    await prisma.parcel.deleteMany({ where: { id: { in: parcels } } });
    await prisma.customer.deleteMany({ where: { id: { in: customers } } });
    await prisma.user.deleteMany({ where: { id: { in: users } } });
    await prisma.organization.deleteMany({ where: { id: { in: organizations } } });
    await new Promise(resolve => server.close(resolve));
    await prisma.$disconnect();
  }
});
