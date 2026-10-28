import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import jwt from 'jsonwebtoken';
import app from '../src/app.js';
import { prisma } from '../src/db.js';
import { JWT_SECRET } from '../src/config.js';
import { quote, matchingError } from '../src/connect_rules.js';

test('Connect pricing uses actual kg for capacity and category-specific fees', () => {
  assert.equal(quote({ isActive: true, unit: 'KG', amountMinor: 2500 }, { weightKg: 5, quantity: 1 }), 12500);
  assert.equal(quote({ isActive: true, unit: 'ITEM', amountMinor: 10000 }, { weightKg: 2, quantity: 1 }), 10000);
  assert.equal(quote({ isActive: true, unit: 'FLAT', amountMinor: 2500, maxWeightKg: .5 }, { weightKg: .501, quantity: 1 }), null);
  assert.equal(quote({ isActive: true, unit: 'MANUAL', amountMinor: 0 }, { weightKg: 1, quantity: 1 }), null);
  assert.match(matchingError({ status: 'APPROVED', departureAt: new Date(Date.now() + 86400000), origin: 'Lomé, Togo', destination: 'New York, USA', categories: ['CLOTHING'] }, { category: 'CLOTHING', preferredDate: new Date(), parcel: { origin: 'New York, USA', destination: 'Lomé, Togo', weightKg: 1 } }, 15), /direction/);
});

test('Connect domestic → traveller → destination workflow preserves privacy and operational controls', async t => {
  const suffix = randomUUID();
  const prefix = `C${suffix.replace(/-/g, '').slice(0, 4).toUpperCase()}`;
  const org = await prisma.organization.create({ data: { name: `Connect QA ${suffix}`, trackingPrefix: prefix } });
  const server = app.listen(0, '127.0.0.1'); await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const user = async (name, role = 'CUSTOMER', locationId) => prisma.user.create({ data: { email: `${name}-${suffix}@example.com`, fullName: name, phone: '+12145550123', passwordHash: 'test-only', role, organizationId: org.id, locationId } });
  const origin = await prisma.location.create({ data: { organizationId: org.id, name: 'Approved New York partner', code: 'NYC', city: 'New York', country: 'United States', address: 'Approved public receiving street', connectReceiving: true } });
  const destination = await prisma.location.create({ data: { organizationId: org.id, name: 'D2F Lomé receiving team', code: 'LOM', city: 'Lomé', country: 'Togo', address: 'Approved destination street', connectReceiving: true } });
  const admin = await user('connect-admin', 'ADMIN'), sender = await user('private-customer'), traveller = await user('private-traveller'), stranger = await user('unrelated-customer');
  const originStaff = await user('origin-staff', 'STAFF', origin.id), destinationStaff = await user('destination-staff', 'STAFF', destination.id);
  const tokens = new Map([admin, sender, traveller, stranger, originStaff, destinationStaff].map(u => [u.id, jwt.sign({ id: u.id, purpose: 'session', ver: 0 }, JWT_SECRET)]));
  const call = async (path, who = admin, body, method = body ? 'POST' : 'GET') => { const response = await fetch(base + path, { method, headers: { Authorization: `Bearer ${tokens.get(who.id)}`, 'Content-Type': 'application/json' }, ...(body ? { body: JSON.stringify(body) } : {}) }); return { status: response.status, body: await response.json() }; };
  const ok = async (...args) => { const result = await call(...args); assert.ok(result.status >= 200 && result.status < 300, `${args[0]}: ${result.status} ${JSON.stringify(result.body)}`); return result.body; };
  const route = { origin: 'New York, USA', destination: 'Lomé, Togo' };
  const tripInput = { ...route, departureAt: new Date(Date.now() + 14 * 86400000).toISOString(), flightNumber: 'Airline 123', capacityKg: 15, categories: ['CLOTHING', 'LAPTOP', 'DOCUMENTS'], verificationReference: 'PRIVATE-TRAVELLER-VERIFICATION', complianceAcknowledged: true };
  const input = (changes = {}) => ({ ...route, category: 'CLOTHING', quantity: 1, weightKg: 5, description: 'Declared clothing and permitted contents', declaredValueMinor: 20000, recipientName: 'Private Recipient', recipientPhone: '+22890001122', recipientAddress: 'PRIVATE-RECIPIENT-ADDRESS', senderCity: 'Dallas, Texas', senderAddress: 'PRIVATE-SENDER-RETURN-ADDRESS', handoverMode: 'DOMESTIC_SHIPPING', deliveryPreference: 'D2F_PICKUP', preferredDate: new Date(Date.now() + 7 * 86400000).toISOString(), restrictionsAcknowledged: true, clientRequestId: randomUUID(), ...changes });
  let booking, trip;
  try {
    await t.test('traveller registration stays pending and catalogue never exposes private traveller data', async () => {
      trip = await ok('/connect/trips', traveller, tripInput);
      assert.equal(trip.status, 'PENDING_REVIEW');
      assert.equal((await ok('/connect/catalog', sender)).trips.length, 0);
      assert.equal((await call(`/connect/trips/${trip.id}/review`, originStaff, { approved: true })).status, 403);
      await ok(`/connect/trips/${trip.id}/review`, admin, { approved: true, complianceVerified: true, reviewNote: 'Identity, ticket, baggage and compliance verified', receivingLocationId: origin.id });
      const catalog = await ok('/connect/catalog', sender); assert.equal(catalog.trips.length, 1);
      const raw = JSON.stringify(catalog); assert.ok(!raw.includes(traveller.email)); assert.ok(!raw.includes('PRIVATE-TRAVELLER-VERIFICATION')); assert.ok(!raw.includes('travellerId'));
    });
    await t.test('directional pricing, domestic costs and permanent D2F tracking are saved with retry protection', async () => {
      await ok('/connect/rates', admin, { ...route, category: 'CLOTHING', unit: 'KG', amountMinor: 2500 });
      await ok('/connect/rates', admin, { ...route, category: 'DOCUMENTS', unit: 'FLAT', amountMinor: 2500 });
      const data = input({ requestedTripId: trip.id });
      booking = await ok('/connect/bookings', sender, data);
      assert.equal(booking.parcel.serviceType, 'AIR_TRAVELLER'); assert.equal(booking.internationalFeeMinor, 12500); assert.equal(booking.domesticCostMinor, null);
      assert.match(booking.parcel.trackingId, new RegExp(`^${prefix}\\d{12}$`)); assert.equal(booking.parcel.awbNumber, null);
      assert.equal((await ok('/connect/bookings', sender, data)).id, booking.id);
      assert.equal((await call('/connect/bookings', stranger, data)).status, 409);
      assert.equal((await call(`/connect/bookings/${booking.id}`, traveller)).status, 404);
      assert.equal((await call('/connect/operations', traveller)).status, 403);
      assert.equal((await call('/connect/bookings', sender, input({ restrictionsAcknowledged: false }))).status, 400);
      assert.equal((await call(`/connect/bookings/${booking.id}/assign`, admin, { tripId: trip.id })).status, 409);
      const heavyDocs = await ok('/connect/bookings', sender, input({ category: 'DOCUMENTS', weightKg: .6 })); assert.equal(heavyDocs.internationalFeeMinor, null);
      const reversed = await ok('/connect/bookings', sender, input({ origin: route.destination, destination: route.origin })); assert.equal(reversed.internationalFeeMinor, null);
    });
    await t.test('review, assignment, traveller acceptance and D2F confirmation remain separate', async () => {
      await ok(`/connect/bookings/${booking.id}/review`, originStaff, { approved: true, verifiedWeightKg: 5, note: 'Safe clothing contents reviewed' });
      await ok(`/connect/bookings/${booking.id}/assign`, admin, { tripId: trip.id });
      assert.equal((await call(`/connect/bookings/${booking.id}/confirm-assignment`, admin, {})).status, 409);
      const myTrips = await ok('/connect/trips', traveller); const a = myTrips[0].assignments[0];
      const raw = JSON.stringify(myTrips); for (const forbidden of [sender.email, 'PRIVATE-SENDER-RETURN-ADDRESS', 'PRIVATE-RECIPIENT-ADDRESS', 'recipientPhone', 'recipientName', 'senderAddress', 'customerId']) assert.ok(!raw.includes(forbidden), forbidden);
      assert.equal((await call(`/connect/assignments/${a.id}/respond`, stranger, { accepted: true, note: 'unsafe access' })).status, 404);
      await ok(`/connect/assignments/${a.id}/respond`, traveller, { accepted: true, note: 'Permitted clothing accepted for D2F handover' });
      await ok(`/connect/bookings/${booking.id}/confirm-assignment`, admin, {});
      const manifest = await ok(`/connect/trips/${trip.id}/manifest`, traveller); assert.equal(manifest.parcels.length, 1); assert.ok(!JSON.stringify(manifest).includes('PRIVATE-SENDER-RETURN-ADDRESS'));
      assert.equal((await call(`/parcels/${booking.parcelId}/events`, admin, { status: 'RECEIVED' })).status, 409);
      assert.equal((await call(`/parcels/${booking.parcelId}/air-cargo`, admin, { awbNumber: '123-12345678' }, 'PATCH')).status, 409);
    });
    await t.test('concurrent reservations prevent overbooking, and declined assignments release actual weight', async () => {
      const b1 = await ok('/connect/bookings', sender, input({ weightKg: 6, category: 'LAPTOP' }));
      const b2 = await ok('/connect/bookings', sender, input({ weightKg: 6, category: 'LAPTOP' }));
      for (const b of [b1,b2]) await ok(`/connect/bookings/${b.id}/review`, admin, { approved: true, verifiedWeightKg: 6, note: 'Device contents and transport eligibility checked' });
      const attempts = await Promise.all([b1,b2].map(b => call(`/connect/bookings/${b.id}/assign`, admin, { tripId: trip.id })));
      assert.deepEqual(attempts.map(a => a.status).sort(), [200,409]);
      const assigned = attempts[0].status === 200 ? b1 : b2;
      const capacity = (await ok('/connect/trips', traveller))[0]; assert.equal(capacity.remainingKg, 4);
      assert.equal((await call(`/connect/bookings/${assigned.id}/review`, admin, { approved: true, verifiedWeightKg: 11, note: 'Weight changed' })).status, 409);
      const a = capacity.assignments.find(a => a.bookingId === assigned.id);
      await ok(`/connect/assignments/${a.id}/respond`, traveller, { accepted: false, note: 'Traveller declines these contents' });
      assert.equal((await ok('/connect/trips', traveller))[0].remainingKg, 10);
    });
    await t.test('agreed prices remain frozen and verified payments are recorded exactly once', async () => {
      await ok(`/connect/bookings/${booking.id}/quote`, admin, { internationalFeeMinor: 12500, domesticCostMinor: 2200, note: 'Clothing fee plus domestic UPS label' });
      assert.equal((await call(`/connect/bookings/${booking.id}/payment`, admin, { reference: 'PAY-1', amountMinor: 14700 })).status, 409);
      assert.equal((await call(`/connect/bookings/${booking.id}/accept-quote`, sender, { totalMinor: 12500 })).status, 409);
      await ok(`/connect/bookings/${booking.id}/accept-quote`, sender, { totalMinor: 14700 });
      await ok(`/connect/bookings/${booking.id}/payment-instructions`, admin, { instructions: 'Use the verified D2F business payment channel and include your booking number.' });
      assert.match((await ok(`/connect/bookings/${booking.id}`, sender)).paymentInstructions, /booking number/);
      assert.equal((await call(`/connect/bookings/${booking.id}/quote`, admin, { internationalFeeMinor: 1, domesticCostMinor: 1, note: 'Cannot change accepted price' })).status, 409);
      await ok('/connect/rates', admin, { ...route, category: 'CLOTHING', unit: 'KG', amountMinor: 9999 });
      assert.equal((await ok(`/connect/bookings/${booking.id}`, sender)).internationalFeeMinor, 12500);
      const payments = await Promise.all([1,2].map(() => ok(`/connect/bookings/${booking.id}/payment`, admin, { reference: `PAY-${suffix}`, amountMinor: 14700 })));
      assert.equal(payments[0].payment.id, payments[1].payment.id);
      assert.equal(await prisma.connectPayment.count({ where: { bookingId: booking.id } }), 1);
      assert.equal(await prisma.trackingEvent.count({ where: { parcelId: booking.parcelId, status: 'PAYMENT_CONFIRMED' } }), 1);
      assert.equal((await call(`/connect/bookings/${booking.id}/payment`, admin, { reference: 'DIFFERENT', amountMinor: 14700 })).status, 409);
    });
    await t.test('domestic label, protected receiving address, staff intake and single-use collection OTP work', async () => {
      assert.equal((await call(`/connect/bookings/${booking.id}/authorize-handover`, admin, {})).status, 409);
      assert.equal((await call(`/connect/bookings/${booking.id}/domestic`, admin, { carrier: 'UPS', trackingNumber: '1Z-TEST', labelUrl: 'http://unsafe.example/label' })).status, 400);
      await ok(`/connect/bookings/${booking.id}/domestic`, admin, { carrier: 'UPS', trackingNumber: '1Z-TEST', labelUrl: 'https://example.com/secure-label' });
      await ok(`/connect/bookings/${booking.id}/domestic-dispatched`, sender, {});
      assert.equal((await call(`/connect/bookings/${booking.id}/receive`, destinationStaff, { note: 'Wrong warehouse' })).status, 403);
      await ok(`/connect/bookings/${booking.id}/receive`, originStaff, { note: 'Sealed parcel and inspected clothing received' });
      const otp = await ok(`/connect/bookings/${booking.id}/authorize-handover`, originStaff, {}); assert.match(otp.code, /^\d{6}$/);
      const b = await ok(`/connect/bookings/${booking.id}`, sender); assert.ok(!('handoverCodeHash' in b)); assert.ok(!('handoverCodeExpiresAt' in b));
      const a = activeAssignment(b);
      await ok(`/connect/locations/${origin.id}`, admin, { address: origin.address, connectReceiving: false }, 'PATCH');
      assert.equal((await call(`/connect/assignments/${a.id}/collect`, traveller, { code: otp.code, contentsAccepted: true })).status, 409);
      await ok(`/connect/locations/${origin.id}`, admin, { address: origin.address, connectReceiving: true }, 'PATCH');
      const wrong = otp.code === '000000' ? '999999' : '000000';
      assert.equal((await call(`/connect/assignments/${a.id}/collect`, traveller, { code: wrong, contentsAccepted: true })).status, 400);
      assert.equal((await prisma.connectBooking.findUnique({ where: { id: b.id } })).handoverAttempts, 1);
      assert.equal((await call(`/connect/assignments/${a.id}/collect`, traveller, { code: otp.code, contentsAccepted: false })).status, 400);
      await ok(`/connect/assignments/${a.id}/collect`, traveller, { code: otp.code, contentsAccepted: true });
      assert.equal((await call(`/connect/assignments/${a.id}/collect`, traveller, { code: otp.code, contentsAccepted: true })).status, 409);
    });
    await t.test('actual departure freezes manifest, destination team receives and actual recipient handover completes delivery', async () => {
      assert.equal((await call(`/connect/bookings/${booking.id}/deliver`, admin, { recipientName: 'Recipient', evidence: 'ID checked', confirmed: true })).status, 409);
      await ok(`/connect/trips/${trip.id}/depart`, originStaff, { confirmed: true });
      assert.equal((await call(`/connect/bookings/${booking.id}/unassign`, admin, { note: 'Forbidden after departure' })).status, 409);
      assert.equal((await call(`/connect/bookings/${booking.id}/destination-received`, originStaff, { locationId: destination.id, note: 'Wrong staff' })).status, 403);
      await ok(`/connect/bookings/${booking.id}/destination-received`, destinationStaff, { locationId: destination.id, note: 'Traveller handed sealed parcel to destination team' });
      await ok(`/connect/bookings/${booking.id}/ready`, destinationStaff, {});
      const result = await ok(`/connect/bookings/${booking.id}/deliver`, destinationStaff, { recipientName: 'Private Recipient', evidence: 'Recipient identity checked and proof recorded', confirmed: true });
      assert.equal(result.parcel.status, 'DELIVERED'); assert.ok(result.deliveredAt);
      assert.equal((await call(`/connect/bookings/${booking.id}/deliver`, destinationStaff, { recipientName: 'Private Recipient', evidence: 'Duplicate', confirmed: true })).status, 409);
      const track = await ok(`/tracking/${booking.parcel.trackingId}`, stranger); assert.equal(track.status, 'DELIVERED'); assert.equal(track.serviceType, 'AIR_TRAVELLER'); assert.ok(!JSON.stringify(track).includes('Private Recipient'));
    });
    await t.test('missing approved receiving locations remain under admin review', async () => {
      const t2 = await ok('/connect/trips', traveller, tripInput);
      await ok(`/connect/trips/${t2.id}/review`, admin, { approved: true, complianceVerified: true, reviewNote: 'Verified traveller; receiving location pending' });
      const b = await ok('/connect/bookings', sender, input());
      await ok(`/connect/bookings/${b.id}/review`, admin, { approved: true, verifiedWeightKg: 5, note: 'Verified' });
      const rejected = await call(`/connect/bookings/${b.id}/assign`, admin, { tripId: t2.id }); assert.equal(rejected.status, 409); assert.match(rejected.body.error, /no approved receiving location/);
      assert.equal((await ok(`/connect/bookings/${b.id}`, sender)).receivingLocation, null);
    });
  } finally {
    await new Promise(resolve => server.close(resolve));
    const parcels = await prisma.parcel.findMany({ where: { organizationId: org.id }, select: { id: true } }); const ids = parcels.map(p => p.id);
    const bookings = await prisma.connectBooking.findMany({ where: { organizationId: org.id }, select: { id: true } }); const bids = bookings.map(b => b.id);
    await prisma.connectPayment.deleteMany({ where: { organizationId: org.id } });
    await prisma.connectAssignment.deleteMany({ where: { bookingId: { in: bids } } });
    await prisma.connectBooking.deleteMany({ where: { organizationId: org.id } });
    await prisma.connectTrip.deleteMany({ where: { organizationId: org.id } }); await prisma.connectRate.deleteMany({ where: { organizationId: org.id } });
    await prisma.trackingEvent.deleteMany({ where: { parcelId: { in: ids } } }); await prisma.trackingIndex.deleteMany({ where: { parcelId: { in: ids } } });
    await prisma.parcelItem.deleteMany({ where: { parcelId: { in: ids } } }); await prisma.parcel.deleteMany({ where: { organizationId: org.id } });
    await prisma.customer.deleteMany({ where: { organizationId: org.id } }); await prisma.user.deleteMany({ where: { organizationId: org.id } }); await prisma.location.deleteMany({ where: { organizationId: org.id } });
    await prisma.organization.delete({ where: { id: org.id } }); await prisma.$disconnect();
  }
});
function activeAssignment(b) { return b.assignments.find(a => ['PROPOSED','ACCEPTED','CONFIRMED'].includes(a.status)); }
