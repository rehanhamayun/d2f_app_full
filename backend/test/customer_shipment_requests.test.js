import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import jwt from 'jsonwebtoken';
import app from '../src/app.js';
import { prisma } from '../src/db.js';
import { JWT_SECRET } from '../src/config.js';

// ── Shared fixture helpers ───────────────────────────────────────────────────

function listen(app) {
  const server = app.listen(0, '127.0.0.1');
  return new Promise((resolve) => server.once('listening', () => resolve(server)));
}

function tokenForUser(user) {
  return jwt.sign({ id: user.id, purpose: 'session', ver: 0 }, JWT_SECRET, {
    algorithm: 'HS256',
  });
}

async function cleanup({ users = [], parcels = [] }) {
  await prisma.auditLog.deleteMany({ where: { entityId: { in: parcels } } });
  await prisma.parcelImage.deleteMany({ where: { parcelId: { in: parcels } } });
  await prisma.parcelItem.deleteMany({ where: { parcelId: { in: parcels } } });
  await prisma.trackingEvent.deleteMany({ where: { parcelId: { in: parcels } } });
  await prisma.trackingIndex.deleteMany({ where: { parcelId: { in: parcels } } });
  await prisma.parcel.deleteMany({ where: { id: { in: parcels } } });
  await prisma.customer.deleteMany({ where: { userId: { in: users } } });
  await prisma.user.deleteMany({ where: { id: { in: users } } });
}

const baseInput = () => ({
  recipientName: 'Awa Mensah',
  recipientPhone: '+22890011223',
  recipientAddress: 'Agoe Assiyeye, Lome, Togo',
  packageType: 'BOX',
  weightKg: 4.2,
  origin: 'Omaha, NE, USA',
  destination: 'Lomé, Togo',
  method: 'AIR',
  notes: 'Fragile inner box.',
  // The request form requires the truthful-contents acknowledgment.
  restrictionsAcknowledged: true,
});

const pickupInput = () => {
  const when = new Date(Date.now() + 3 * 24 * 60 * 60 * 1000);
  when.setSeconds(0, 0);
  return {
    ...baseInput(),
    deliveryMode: 'PICKUP',
    pickupAddress: '108 Dodge Street, Omaha, NE',
    pickupScheduledAt: when.toISOString(),
    items: [
      { name: 'Clothing box', quantity: 2, weightKg: 3.5, lengthCm: 60, widthCm: 40, heightCm: 45 },
      { name: 'Kitchen blender', type: 'APPLIANCE', quantity: 1, details: 'Retail box', weightKg: 1.2 },
    ],
  };
};

test('customer shipment requests carry many items, a pickup schedule and goods photos', async () => {
  const server = await listen(app);
  const suffix = randomUUID();
  const users = [];
  const parcels = [];
  try {
    const { customer, omaha, customerToken, staffToken, request } = await withFixture(
      server,
      suffix,
      users,
    );

    // A customer without a phone number on file cannot request a shipment:
    // D2F staff must always be able to reach the sender.
    const noPhoneUser = await prisma.user.create({
      data: {
        email: `phoneless-${suffix}@example.com`,
        fullName: 'No Phone Customer',
        passwordHash: 'unused',
        role: 'CUSTOMER',
        organizationId: customer.organizationId,
      },
    });
    users.push(noPhoneUser.id);
    const phonelessCreate = await request('/customer/parcels', {
      token: tokenForUser(noPhoneUser),
      method: 'POST',
      data: pickupInput(),
    });
    assert.equal(phonelessCreate.status, 400);
    assert.match(phonelessCreate.body.error, /phone/i);

    // Pickup requests need a collection address and a future slot.
    const missingAddress = await request('/customer/parcels', {
      token: customerToken,
      method: 'POST',
      data: { ...pickupInput(), pickupAddress: '   ' },
    });
    assert.equal(missingAddress.status, 400);
    assert.match(missingAddress.body.error, /collection address/i);

    // The truthful-declaration acknowledgment is compulsory on the form.
    const unacknowledged = await request('/customer/parcels', {
      token: customerToken,
      method: 'POST',
      data: { ...pickupInput(), restrictionsAcknowledged: false },
    });
    assert.equal(unacknowledged.status, 400);
    assert.match(unacknowledged.body.error, /restrictions/i);

    const pastSchedule = await request('/customer/parcels', {
      token: customerToken,
      method: 'POST',
      data: {
        ...pickupInput(),
        pickupScheduledAt: new Date(Date.now() - 24 * 3600 * 1000).toISOString(),
      },
    });
    assert.equal(pastSchedule.status, 400);
    assert.match(pastSchedule.body.error, /pickup date/i);

    const tooManyItems = await request('/customer/parcels', {
      token: customerToken,
      method: 'POST',
      data: {
        ...pickupInput(),
        items: Array.from({ length: 21 }, (_, i) => ({ name: `Item ${i + 1}` })),
      },
    });
    assert.equal(tooManyItems.status, 400);

    const badItem = await request('/customer/parcels', {
      token: customerToken,
      method: 'POST',
      data: { ...pickupInput(), items: [{ name: 'x'.repeat(121) }] },
    });
    assert.equal(badItem.status, 400);

    // Happy path: pickup with itemized goods, schedule and collection contact.
    const created = await request('/customer/parcels', {
      token: customerToken,
      method: 'POST',
      data: { ...pickupInput(), clientRequestId: `customer-${suffix}` },
    });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const parcel = created.body;
    parcels.push(parcel.id);
    assert.equal(parcel.status, 'REQUESTED');
    assert.equal(parcel.deliveryMode, 'PICKUP');
    assert.ok(parcel.pickupAddress, 'collection address saved');
    assert.ok(parcel.pickupScheduledAt);
    assert.deepEqual(
      parcel.items.map((item) => item.name),
      ['Clothing box', 'Kitchen blender'],
    );
    assert.equal(parcel.items[0].quantity, 2);
    assert.equal(parcel.items[0].type, 'BOX');
    assert.equal(parcel.items[0].lengthCm, 60);
    assert.equal(parcel.items[1].type, 'APPLIANCE');
    assert.ok(parcel.restrictionsAcknowledgedAt, 'declaration acknowledgment recorded');
    assert.match(parcel.events[0].note, /collection/i);

    // The linked customer profile carries the compulsory contact details.
    const profile = await prisma.customer.findUniqueOrThrow({
      where: { userId: customer.id },
    });
    assert.equal(profile.phone, customer.phone);
    assert.equal(profile.email, customer.email);

    // A retry with the same request key returns the same shipment, without
    // duplicating the goods list.
    const retried = await request('/customer/parcels', {
      token: customerToken,
      method: 'POST',
      data: { ...pickupInput(), clientRequestId: `customer-${suffix}` },
    });
    assert.equal(retried.status, 200);
    assert.equal(retried.body.id, parcel.id);
    assert.equal(retried.body.items.length, 2);
    const itemCount = await prisma.parcelItem.count({ where: { parcelId: parcel.id } });
    assert.equal(itemCount, 2);

    const list = await request('/customer/parcels', { token: customerToken });
    assert.equal(list.body.length, 1);
    assert.equal(list.body[0].items.length, 2);
    assert.equal(list.body[0].deliveryMode, 'PICKUP');

    // Staff confirm the pickup window (optionally adjusting it), then collect
    // without naming a facility — the goods are at the customer's door, not in
    // a warehouse yet. Intake at the warehouse still needs facility+proof.
    const schedule = await request(`/parcels/${parcel.id}/events`, {
      token: staffToken,
      method: 'POST',
      data: {
        status: 'PICKUP_SCHEDULED',
        pickupScheduledAt: new Date(Date.now() + 4 * 24 * 3600 * 1000).toISOString(),
        note: 'Driver assigned for the afternoon window.',
      },
    });
    assert.equal(schedule.status, 201, JSON.stringify(schedule.body));

    const picked = await request(`/parcels/${parcel.id}/events`, {
      token: staffToken,
      method: 'POST',
      data: { status: 'PICKED_UP', note: 'Collected from the customer address.' },
    });
    assert.equal(picked.status, 201, JSON.stringify(picked.body));

    const received = await request(`/parcels/${parcel.id}/events`, {
      token: staffToken,
      method: 'POST',
      data: { status: 'RECEIVED', locationId: omaha.id, confirmed: true },
    });
    assert.equal(received.status, 201, JSON.stringify(received.body));

    // The staff record shows the goods and the confirmed collection.
    const detail = await request(`/parcels/${parcel.id}`, { token: staffToken });
    assert.equal(detail.status, 200);
    assert.equal(detail.body.items.length, 2);
    assert.equal(detail.body.status, 'RECEIVED');
    assert.equal(detail.body.deliveryMode, 'PICKUP');
    assert.ok(detail.body.pickupScheduledAt);
  } finally {
    await cleanup({ users, parcels });
    await new Promise((resolve) => server.close(resolve));
    await prisma.$disconnect();
  }
});

test('declared packages carry type and dimensions, collection records misses and intake allocates package codes', async () => {
  const server = await listen(app);
  const suffix = randomUUID();
  const users = [];
  const parcels = [];
  try {
    const { omaha, customerToken, staffToken, adminToken, request } = await withFixture(server, suffix, users);

    const input = () => ({
      ...pickupInput(),
      items: [
        { name: 'Box of books', type: 'BOX', quantity: 1, weightKg: 12, lengthCm: 50, widthCm: 40, heightCm: 30 },
        { name: 'Barrel of household goods', type: 'BARREL', quantity: 1, details: 'Sealed with plastic', weightKg: 60 },
        { name: 'Suitcase', type: 'SUITCASE', quantity: 1, weightKg: 18 },
      ],
    });

    // Half a dimension set is not a package measurement.
    const halfDims = await request('/customer/parcels', {
      token: customerToken,
      method: 'POST',
      data: { ...input(), items: [{ name: 'Half box', lengthCm: 50, widthCm: 40 }] },
    });
    assert.equal(halfDims.status, 400);
    assert.match(halfDims.body.error, /all three/i);
    const badType = await request('/customer/parcels', {
      token: customerToken,
      method: 'POST',
      data: { ...input(), items: [{ name: 'Odd package', type: 'SKY' }] },
    });
    assert.equal(badType.status, 400);
    assert.match(badType.body.error, /package type/i);

    const created = await request('/customer/parcels', {
      token: customerToken,
      method: 'POST',
      data: input(),
    });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const parcel = created.body;
    parcels.push(parcel.id);
    const itemIds = parcel.items.map((item) => item.id);
    assert.equal(parcel.items[2].type, 'SUITCASE');

    // A photo can document one declared package; an unknown itemId is rejected.
    const jpeg = Buffer.concat([
      Buffer.from([0xff, 0xd8, 0xff, 0xe0]),
      Buffer.from(randomUUID().split('').map((c) => c.charCodeAt(0))),
      Buffer.from([0xff, 0xd9]),
    ]);
    const badLink = await request(
      `/customer/parcels/${parcel.id}/images?itemId=not-a-package&name=barrel.jpg`,
      { token: customerToken, method: 'POST', data: jpeg, headers: { 'Content-Type': 'image/jpeg' } },
    );
    assert.equal(badLink.status, 400);
    const linked = await request(
      `/customer/parcels/${parcel.id}/images?itemId=${itemIds[1]}&name=${encodeURIComponent('barrel.jpg')}`,
      { token: customerToken, method: 'POST', data: jpeg, headers: { 'Content-Type': 'image/jpeg' } },
    );
    assert.equal(linked.status, 201, JSON.stringify(linked.body));
    assert.equal(linked.body.itemId, itemIds[1]);

    // Staff schedule the pickup, then move the slot with a recorded reason.
    const schedule = await request(`/parcels/${parcel.id}/events`, {
      token: staffToken,
      method: 'POST',
      data: { status: 'PICKUP_SCHEDULED', pickupScheduledAt: parcel.pickupScheduledAt },
    });
    assert.equal(schedule.status, 201, JSON.stringify(schedule.body));

    const slotBefore = await prisma.parcel.findUniqueOrThrow({
      where: { id: parcel.id },
      select: { pickupScheduledAt: true, updatedAt: true },
    });
    const newSlot = new Date(slotBefore.pickupScheduledAt.getTime() + 12 * 3600 * 1000);
    const rescheduled = await request(`/parcels/${parcel.id}`, {
      token: adminToken,
      method: 'PATCH',
      data: {
        pickupScheduledAt: newSlot.toISOString(),
        rescheduleReason: 'Truck could not enter the street before noon.',
        updatedAt: slotBefore.updatedAt.toISOString(),
      },
    });
    assert.equal(rescheduled.status, 200, JSON.stringify(rescheduled.body));
    const sameSlot = await request(`/parcels/${parcel.id}`, {
      token: adminToken, method: 'PATCH',
      data: { pickupScheduledAt: newSlot.toISOString(), updatedAt: rescheduled.body.updatedAt },
    });
    assert.equal(sameSlot.status, 200);
    const detailAfterMove = await request(`/parcels/${parcel.id}`, { token: staffToken });
    const rescheduleEvent = detailAfterMove.body.events.find((event) =>
      /Pickup rescheduled/.test(event.note || ''),
    );
    assert.ok(rescheduleEvent, 'reschedule recorded in the timeline');
    assert.equal(detailAfterMove.body.events.filter((event) => /Pickup rescheduled/.test(event.note || '')).length, 1);
    assert.match(rescheduleEvent.note, /Truck could not enter the street/);

    // Invalid outcomes are refused before anything is written.
    const strangerItem = await request(`/parcels/${parcel.id}/events`, {
      token: staffToken,
      method: 'POST',
      data: { status: 'PICKED_UP', missedItems: [{ itemId: 'no-such-package', reason: 'xyz' }] },
    });
    assert.equal(strangerItem.status, 400);
    const noReason = await request(`/parcels/${parcel.id}/events`, {
      token: staffToken,
      method: 'POST',
      data: { status: 'PICKED_UP', missedItems: [{ itemId: itemIds[0], reason: '   ' }] },
    });
    assert.equal(noReason.status, 400);

    // Collection records the discrepancy: five declared, three seen on hand.
    const noneCollected = await request(`/parcels/${parcel.id}/events`, {
      token: staffToken, method: 'POST',
      data: { status: 'PICKED_UP', missedItems: itemIds.map((itemId) => ({ itemId, reason: 'Customer unavailable' })) },
    });
    assert.equal(noneCollected.status, 400);
    assert.equal(await prisma.parcelItem.count({ where: { parcelId: parcel.id, collectedAt: { not: null } } }), 0);

    const missed = await request(`/parcels/${parcel.id}/events`, {
      token: staffToken,
      method: 'POST',
      data: {
        status: 'PICKED_UP',
        note: 'Collected at the customer address.',
        missedItems: [
          { itemId: itemIds[1], reason: 'Barrel arrived at the collection window already loaded for a later trip.' },
        ],
      },
    });
    assert.equal(missed.status, 201, JSON.stringify(missed.body));
    const collectedRow = await prisma.parcelItem.findUniqueOrThrow({ where: { id: itemIds[0] } });
    const missedRow = await prisma.parcelItem.findUniqueOrThrow({ where: { id: itemIds[1] } });
    assert.equal(collectedRow.collectedAt != null, true);
    assert.equal(collectedRow.notCollectedReason, null);
    assert.equal(collectedRow.packageCode, `${parcel.trackingId}-P01`);
    assert.equal(missedRow.collectedAt, null);
    assert.equal(missedRow.packageCode, null);
    assert.match(missedRow.notCollectedReason, /Barrel arrived/);

    const packageLookup = await request(`/parcels/${collectedRow.packageCode}`, { token: staffToken });
    assert.equal(packageLookup.status, 200);
    assert.equal(packageLookup.body.id, parcel.id);
    const packageTracking = await request(`/tracking/${collectedRow.packageCode}`, { token: customerToken });
    assert.equal(packageTracking.status, 200);
    assert.deepEqual(Object.keys(packageTracking.body).sort(), ['events', 'method', 'serviceType', 'status', 'trackingId']);
    assert.equal(packageTracking.body.trackingId, parcel.trackingId);
    const unknownCode = await request(`/parcels/${parcel.trackingId}-P02`, { token: staffToken });
    assert.equal(unknownCode.status, 404);

    // Warehouse custody: package sub-IDs P01… allocated with parcel-tracking
    // prefix, stable per declared order.
    const received = await request(`/parcels/${parcel.id}/events`, {
      token: staffToken,
      method: 'POST',
      data: { status: 'RECEIVED', locationId: omaha.id, confirmed: true, note: 'Intake; barrel still missing.' },
    });
    assert.equal(received.status, 201, JSON.stringify(received.body));
    const detail = await request(`/parcels/${parcel.id}`, { token: staffToken });
    assert.deepEqual(
      detail.body.items.map((item) => item.packageCode),
      [
        `${parcel.trackingId}-P01`,
        null,
        `${parcel.trackingId}-P03`,
      ],
    );

    const clearedSlot = await request(`/parcels/${parcel.id}`, {
      token: adminToken, method: 'PATCH',
      data: { pickupScheduledAt: null, updatedAt: detail.body.updatedAt },
    });
    assert.equal(clearedSlot.status, 200);
    assert.equal(clearedSlot.body.pickupScheduledAt, null);
    assert.ok(clearedSlot.body.events.some((event) => /Pickup slot cleared/.test(event.note || '')));

    // The record stays frozen as evidence later; codes do not move either.
    const frozen = await request(`/customer/parcels/${parcel.id}/images?name=late.jpg`, {
      token: customerToken,
      method: 'POST',
      data: jpeg,
      headers: { 'Content-Type': 'image/jpeg' },
    });
    assert.equal(frozen.status, 409);
  } finally {
    await cleanup({ users, parcels });
    await new Promise((resolve) => server.close(resolve));
    await prisma.$disconnect();
  }
});

test('drop-off requests cannot enter pickup stages and receive a straight intake', async () => {
  const server = await listen(app);
  const suffix = randomUUID();
  const users = [];
  const parcels = [];
  try {
    const { omaha, customerToken, staffToken, request } = await withFixture(server, suffix, users);

    const created = await request('/customer/parcels', {
      token: customerToken,
      method: 'POST',
      data: {
        ...baseInput(),
        deliveryMode: 'DROP_OFF',
        pickupAddress: 'Customer brings the bags to the D2F Omaha warehouse',
        items: [{ name: 'Bag of folded goods', quantity: 1 }],
      },
    });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const parcel = created.body;
    parcels.push(parcel.id);
    assert.equal(parcel.deliveryMode, 'DROP_OFF');
    assert.equal(parcel.pickupScheduledAt, null);

    const scheduled = await request(`/parcels/${parcel.id}/events`, {
      token: staffToken,
      method: 'POST',
      data: { status: 'PICKUP_SCHEDULED' },
    });
    assert.equal(scheduled.status, 400);
    assert.match(scheduled.body.error, /not requested for pickup/i);

    const picked = await request(`/parcels/${parcel.id}/events`, {
      token: staffToken,
      method: 'POST',
      data: { status: 'PICKED_UP' },
    });
    assert.equal(picked.status, 400);

    // Warehouse intake is confirmed exactly as before.
    const received = await request(`/parcels/${parcel.id}/events`, {
      token: staffToken,
      method: 'POST',
      data: { status: 'RECEIVED', locationId: omaha.id, confirmed: true },
    });
    assert.equal(received.status, 201, JSON.stringify(received.body));

    // Once the warehouse verified intake, the request section is frozen.
    const upload = await request(`/customer/parcels/${parcel.id}/images`, {
      token: customerToken,
      method: 'POST',
      data: Buffer.from(pngBytes()),
      headers: { 'Content-Type': 'image/png' },
    });
    assert.equal(upload.status, 409);
  } finally {
    await cleanup({ users, parcels });
    await new Promise((resolve) => server.close(resolve));
    await prisma.$disconnect();
  }
});

test('goods photos upload, serve and freeze with the order lifecycle', async () => {
  const server = await listen(app);
  const suffix = randomUUID();
  const users = [];
  const parcels = [];
  try {
    const { omaha, customerToken, otherToken, staffToken, request } = await withFixture(
      server,
      suffix,
      users,
    );

    const created = await request('/customer/parcels', {
      token: customerToken,
      method: 'POST',
      data: pickupInput(),
    });
    assert.equal(created.status, 201);
    const parcel = created.body;
    parcels.push(parcel.id);

    // Unsupported content types are rejected before any storage work.
    const wrongType = await request(`/customer/parcels/${parcel.id}/images`, {
      token: customerToken,
      method: 'POST',
      data: Buffer.from('text/plain, definitively'),
      headers: { 'Content-Type': 'text/plain' },
    });
    assert.equal(wrongType.status, 415);

    // Oversized uploads report a friendly limit.
    const huge = Buffer.alloc(4 * 1024 * 1024 + 64, 7);
    const oversized = await request(`/customer/parcels/${parcel.id}/images`, {
      token: customerToken,
      method: 'POST',
      data: huge,
      headers: { 'Content-Type': 'image/jpeg' },
    });
    assert.equal(oversized.status, 413);

    // A small JPEG uploads and its bytes round-trip exactly through the API.
    const jpeg = Buffer.concat([
      Buffer.from([0xff, 0xd8, 0xff, 0xe0]),
      Buffer.from(randomUUID().split('').map((c) => c.charCodeAt(0))),
      Buffer.from([0xff, 0xd9]),
    ]);
    const upload = await request(
      `/customer/parcels/${parcel.id}/images?label=${encodeURIComponent('Front of the box')}&name=${encodeURIComponent('front.jpg')}`,
      {
        token: customerToken,
        method: 'POST',
        data: jpeg,
        headers: { 'Content-Type': 'image/jpeg' },
      },
    );
    assert.equal(upload.status, 201, JSON.stringify(upload.body));
    assert.equal(upload.body.fileName, 'front.jpg');
    assert.equal(upload.body.sizeBytes, jpeg.length);

    const list = await request(`/customer/parcels/${parcel.id}/images`, {
      token: customerToken,
    });
    assert.equal(list.status, 200);
    assert.equal(list.body.length, 1);
    assert.equal(list.body[0].contentType, 'image/jpeg');

    const raw = await fetch(`${base(server)}/customer/parcels/${parcel.id}/images/${upload.body.id}/raw`, {
      headers: { Authorization: `Bearer ${customerToken}` },
    });
    assert.equal(raw.status, 200);
    assert.equal(raw.headers.get('content-type'), 'image/jpeg');
    assert.deepEqual([...Buffer.from(await raw.arrayBuffer())], [...jpeg]);

    // Other customers cannot see or serve each other's photos.
    const stranger = await request(`/customer/parcels/${parcel.id}/images`, {
      token: otherToken,
    });
    assert.equal(stranger.status, 404);
    const strangerRaw = await fetch(
      `${base(server)}/customer/parcels/${parcel.id}/images/${upload.body.id}/raw`,
      { headers: { Authorization: `Bearer ${otherToken}` } },
    );
    assert.equal(strangerRaw.status, 404);

    // Staff see the shipment's photos through the operations record.
    const staffImage = await fetch(`${base(server)}/parcels/${parcel.id}/images/${upload.body.id}/raw`, {
      headers: { Authorization: `Bearer ${staffToken}` },
    });
    assert.equal(staffImage.status, 200);
    assert.deepEqual([...Buffer.from(await staffImage.arrayBuffer())], [...jpeg]);

    // Cap: eight photos per shipment.
    for (let i = 0; i < 7; i += 1) {
      const extra = await request(`/customer/parcels/${parcel.id}/images`, {
        token: customerToken,
        method: 'POST',
        data: jpeg,
        headers: { 'Content-Type': 'image/webp' },
      });
      assert.equal(extra.status, 201, `photo ${i + 2}`);
    }
    const ninth = await request(`/customer/parcels/${parcel.id}/images`, {
      token: customerToken,
      method: 'POST',
      data: jpeg,
      headers: { 'Content-Type': 'image/png' },
    });
    assert.equal(ninth.status, 409);

    // Deleting is owner-only while the request is still being processed.
    const removed = await request(`/customer/parcels/${parcel.id}/images/${upload.body.id}`, {
      token: customerToken,
      method: 'DELETE',
    });
    assert.equal(removed.status, 204);
    const again = await request(`/customer/parcels/${parcel.id}/images/${upload.body.id}`, {
      token: customerToken,
      method: 'DELETE',
    });
    assert.equal(again.status, 404);

    // The frozen gallery stays visible to staff after intake.
    const received = await request(`/parcels/${parcel.id}/events`, {
      token: staffToken,
      method: 'POST',
      data: { status: 'RECEIVED', locationId: omaha.id, confirmed: true },
    });
    assert.equal(received.status, 201, JSON.stringify(received.body));
    const frozenUpload = await request(`/customer/parcels/${parcel.id}/images`, {
      token: customerToken,
      method: 'POST',
      data: jpeg,
      headers: { 'Content-Type': 'image/jpeg' },
    });
    assert.equal(frozenUpload.status, 409);
    const staffDetail = await request(`/parcels/${parcel.id}`, { token: staffToken });
    assert.equal(staffDetail.status, 200);
    assert.equal(staffDetail.body.images.length, 7);
  } finally {
    await cleanup({ users, parcels });
    await new Promise((resolve) => server.close(resolve));
    await prisma.$disconnect();
  }
});

const base = (server) => `http://127.0.0.1:${server.address().port}`;

// A valid PNG signature padded over 16 bytes for uploads that need only the
// content-type check.
function pngBytes() {
  return [
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  ];
}

async function withFixture(server, suffix, users) {
  // The seed's permanent D2F organization — selecting it by id keeps the
  // fixture immune to parallel suites creating and removing their own orgs.
  const organization = await prisma.organization.findUniqueOrThrow({
    where: { id: 'org-d2f' },
  });
  const omaha = await prisma.location.findFirstOrThrow({
    where: { organizationId: organization.id, code: 'OMA-1' },
  });
  const customer = await prisma.user.create({
    data: {
      email: `cust-${suffix}@example.com`,
      fullName: 'Shipment Request Customer',
      phone: '+22890031122',
      passwordHash: 'unused',
      role: 'CUSTOMER',
      organizationId: organization.id,
    },
  });
  const otherCustomer = await prisma.user.create({
    data: {
      email: `other-${suffix}@example.com`,
      fullName: 'Shipment Request Other',
      phone: '+22890061133',
      passwordHash: 'unused',
      role: 'CUSTOMER',
      organizationId: organization.id,
    },
  });
  const staff = await prisma.user.create({
    data: {
      email: `staff-${suffix}@example.com`,
      fullName: 'Shipment Request Staff',
      passwordHash: 'unused',
      role: 'STAFF',
      organizationId: organization.id,
      locationId: omaha.id,
    },
  });
  const admin = await prisma.user.create({
    data: {
      email: `admin-${suffix}@example.com`,
      fullName: 'Shipment Request Admin',
      passwordHash: 'unused',
      role: 'ADMIN',
      organizationId: organization.id,
      locationId: omaha.id,
    },
  });
  users.push(customer.id, otherCustomer.id, staff.id, admin.id);
  const customerToken = tokenForUser(customer);
  const otherToken = tokenForUser(otherCustomer);
  const staffToken = tokenForUser(staff);
  const adminToken = tokenForUser(admin);

  const port = server.address().port;
  async function request(path, { token, method = 'GET', data, headers = {} } = {}) {
    const hasBody = data !== undefined;
    const response = await fetch(`http://127.0.0.1:${port}${path}`, {
      method,
      headers: {
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(hasBody ? { 'Content-Type': headers['Content-Type'] || 'application/json' } : {}),
        ...headers,
      },
      ...(hasBody ? { body: data instanceof Buffer ? data : JSON.stringify(data) } : {}),
    });
    const type = response.headers.get('content-type') || '';
    return {
      status: response.status,
      headers: response.headers,
      body: type.includes('json') ? await response.json() : await response.text(),
    };
  }

  return { organization, omaha, customer, otherCustomer, staff, admin, customerToken, otherToken, staffToken, adminToken, request };
}
