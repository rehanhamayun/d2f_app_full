import { Router } from 'express';
import { createHash, randomInt, timingSafeEqual } from 'node:crypto';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { generateTrackingId, resolveOrganizationId } from '../tracking.js';
import { CATEGORIES, ACTIVE_ASSIGNMENTS, routeKey, fail, text, number, future, quote, effectiveWeight, matchingError, approvedLocationMatches } from '../connect_rules.js';

const router = Router();
const operations = user => ['ADMIN', 'STAFF'].includes(user.role);
const active = booking => booking.assignments.find(a => ACTIVE_ASSIGNMENTS.includes(a.status));
const bookingInclude = {
  parcel: { include: { customer: true, items: { orderBy: { position: 'asc' } }, events: { orderBy: { createdAt: 'asc' } } } },
  assignments: { include: { trip: { include: { receivingLocation: true } } }, orderBy: { createdAt: 'desc' } },
  receivingLocation: true, payment: true,
};
const tripInclude = { traveller: { select: { id: true, fullName: true, email: true, phone: true } }, receivingLocation: true,
  assignments: { include: { booking: { include: { parcel: true, payment: true, receivingLocation: true } } } } };
const safeLocation = location => location && ({ id: location.id, name: location.name, address: location.address, city: location.city, country: location.country });
const safeTrip = trip => ({ id: trip.id, origin: trip.origin, destination: trip.destination, departureAt: trip.departureAt,
  flightNumber: trip.flightNumber, capacityKg: trip.capacityKg, categories: trip.categories, status: trip.status,
  receivingLocation: safeLocation(trip.receivingLocation) });
const remaining = trip => Math.round((trip.capacityKg - trip.assignments.filter(a => ACTIVE_ASSIGNMENTS.includes(a.status)).reduce((sum, a) => sum + effectiveWeight(a.booking), 0)) * 1000) / 1000;
function customerBooking(b) {
  const { handoverCodeHash, handoverCodeExpiresAt, handoverAttempts, assignments, parcel, ...rest } = b;
  // The owner sees their own booking, never the traveller's private profile.
  return { ...rest, receivingLocation: safeLocation(b.receivingLocation), parcel: { ...parcel, customer: undefined },
    assignments: assignments.map(a => ({ id: a.id, status: a.status, acceptedAt: a.acceptedAt, confirmedAt: a.confirmedAt, trip: safeTrip(a.trip) })) };
}
function staffBooking(b) {
  const { handoverCodeHash, handoverCodeExpiresAt, handoverAttempts, ...rest } = b;
  return rest;
}
function travellerAssignment(a) {
  const b = a.booking;
  return { id: a.id, status: a.status, responseNote: a.responseNote, bookingId: b.id,
    trackingId: b.parcel.trackingId, category: b.category, quantity: b.quantity, description: b.parcel.notes,
    weightKg: effectiveWeight(b), origin: b.parcel.origin, destination: b.parcel.destination,
    parcelStatus: b.parcel.status, collectedAt: b.collectedAt,
    contentsVerifiedAt: b.contentsVerifiedAt, receivingLocation: safeLocation(b.receivingLocation) };
}
const wrap = fn => async (req, res, next) => { try { await fn(req, res); } catch (error) { next(error); } };
router.use(authenticate, requireRole('CUSTOMER', 'STAFF', 'ADMIN'), async (req, _res, next) => {
 try {
  const linked = !req.user.organizationId ? await prisma.customer.findUnique({ where: { userId: req.user.id }, select: { organizationId: true } }) : null;
  req.connectOrg = await resolveOrganizationId(prisma, { ...req.user, organizationId: req.user.organizationId || linked?.organizationId });
  next();
 } catch (error) { next(error); }
});
async function transaction(req, fn) {
  return prisma.$transaction(async tx => {
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${`connect:${req.connectOrg}`}, 0))`;
    return fn(tx);
  }, { timeout: 15000 });
}
async function getBooking(tx, req, id = req.params.id) {
  const b = await tx.connectBooking.findFirst({ where: { id, organizationId: req.connectOrg,
    ...(!operations(req.user) ? { parcel: { customer: { userId: req.user.id } } } : {}) }, include: bookingInclude });
  if (!b) fail(404, 'D2F Connect booking not found.');
  return b;
}
async function getTrip(tx, req) {
  const trip = await tx.connectTrip.findFirst({ where: { id: req.params.id, organizationId: req.connectOrg,
    ...(!operations(req.user) ? { travellerId: req.user.id } : {}) }, include: tripInclude });
  if (!trip) fail(404, 'Traveller trip not found.');
  return trip;
}
async function audit(tx, req, entity, id, action, detail) {
  await tx.auditLog.create({ data: { actorId: req.user.id, entity, entityId: id, action: `CONNECT_${action}`, detail } });
}
async function event(tx, req, b, status, note, advance = true) {
  if (advance) await tx.parcel.update({ where: { id: b.parcelId }, data: { status } });
  await tx.trackingEvent.create({ data: { parcelId: b.parcelId, status: advance ? status : b.parcel.status, actorId: req.user.id, note } });
  await audit(tx, req, 'ConnectBooking', b.id, status, note);
}
function facility(req, location) {
  if (!location?.connectReceiving) fail(409, 'Select an approved D2F receiving location.');
  if (req.user.role === 'STAFF' && req.user.locationId !== location.id) fail(403, 'Your assigned facility must confirm this physical handover.');
}
function editable(b) {
  if (b.collectedAt || b.deliveredAt || ['REJECTED', 'CANCELLED'].includes(b.parcel.status)) fail(409, 'This booking is closed to intake changes.');
  if (active(b)?.trip.status === 'DEPARTED' || active(b)?.trip.status === 'ARRIVED') fail(409, 'The traveller has departed. An audited exception review is required.');
}

router.get('/catalog', wrap(async (req, res) => {
  const [trips, rates] = await Promise.all([
    prisma.connectTrip.findMany({ where: { organizationId: req.connectOrg, status: 'APPROVED', departureAt: { gt: new Date() } }, include: tripInclude, orderBy: { departureAt: 'asc' } }),
    prisma.connectRate.findMany({ where: { organizationId: req.connectOrg, isActive: true }, orderBy: [{ origin: 'asc' }, { category: 'asc' }] }),
  ]);
  res.json({ categories: CATEGORIES, trips: trips.map(t => ({ ...safeTrip(t), remainingKg: remaining(t) })), rates });
}));
router.get('/operations', requireRole('STAFF', 'ADMIN'), wrap(async (req, res) => {
  const [trips, bookings, rates, locations] = await Promise.all([
    prisma.connectTrip.findMany({ where: { organizationId: req.connectOrg }, include: tripInclude, orderBy: { createdAt: 'desc' } }),
    prisma.connectBooking.findMany({ where: { organizationId: req.connectOrg }, include: bookingInclude, orderBy: { createdAt: 'desc' } }),
    prisma.connectRate.findMany({ where: { organizationId: req.connectOrg } }),
    prisma.location.findMany({ where: { organizationId: req.connectOrg }, orderBy: { name: 'asc' } }),
  ]);
  res.json({ bookings: bookings.map(staffBooking), rates, locations, trips: trips.map(t => {
    const revenueMinor = t.assignments.filter(a => a.status === 'CONFIRMED' && a.booking.payment).reduce((sum, a) => sum + a.booking.internationalFeeMinor, 0);
    return { ...t, assignments: t.assignments.map(travellerAssignment), remainingKg: remaining(t), revenueMinor,
      profitMinor: revenueMinor - t.compensationMinor - t.expensesMinor };
  }) });
}));
router.post('/rates', requireRole('ADMIN'), wrap(async (req, res) => {
  const b = req.body || {};
  const origin = text(b.origin, 'departure city and country'); const destination = text(b.destination, 'destination city and country');
  if (routeKey(origin) === routeKey(destination)) fail(400, 'Choose two different route locations.');
  if (!CATEGORIES.includes(b.category) || !['KG', 'ITEM', 'FLAT', 'MANUAL'].includes(b.unit)) fail(400, 'Choose a category and rate unit.');
  if (b.category === 'OTHER' && b.unit !== 'MANUAL') fail(400, 'Exceptional items require a manual quotation.');
  const amountMinor = number(b.amountMinor, 'rate in cents', 0, 100000000, true);
  const maxWeightKg = b.category === 'DOCUMENTS' ? 0.5 : b.maxWeightKg == null ? null : number(b.maxWeightKg, 'maximum weight', 0.001, 100);
  res.json(await transaction(req, async tx => {
    const rate = await tx.connectRate.upsert({ where: { organizationId_origin_destination_category: { organizationId: req.connectOrg, origin, destination, category: b.category } },
      create: { organizationId: req.connectOrg, origin, destination, category: b.category, unit: b.unit, amountMinor, maxWeightKg },
      update: { unit: b.unit, amountMinor, maxWeightKg, isActive: b.isActive !== false } });
    await audit(tx, req, 'ConnectRate', rate.id, 'RATE_SAVED', JSON.stringify({ origin, destination, category: b.category, unit: b.unit, amountMinor }));
    return rate;
  }));
}));
router.patch('/locations/:id', requireRole('ADMIN'), wrap(async (req, res) => {
  const address = text(req.body?.address, 'the public receiving address', 500);
  res.json(await transaction(req, async tx => {
    const l = await tx.location.findFirst({ where: { id: req.params.id, organizationId: req.connectOrg } });
    if (!l?.city || !l.country) fail(400, 'Add the location city and country in Locations first.');
    if (typeof req.body.connectReceiving !== 'boolean') fail(400, 'Choose whether this location is approved.');
    const location = await tx.location.update({ where: { id: l.id }, data: { address, connectReceiving: req.body.connectReceiving } });
    await audit(tx, req, 'Location', l.id, 'RECEIVING_LOCATION_UPDATED', JSON.stringify({ address, connectReceiving: location.connectReceiving }));
    return location;
  }));
}));
router.get('/trips', wrap(async (req, res) => {
  const trips = await prisma.connectTrip.findMany({ where: { organizationId: req.connectOrg, ...(!operations(req.user) ? { travellerId: req.user.id } : {}) }, include: tripInclude, orderBy: { departureAt: 'asc' } });
  res.json(trips.map(t => ({ ...safeTrip(t), reviewNote: t.reviewNote, remainingKg: remaining(t), assignments: t.assignments.map(travellerAssignment) })));
}));
router.post('/trips', requireRole('CUSTOMER'), wrap(async (req, res) => {
  const b = req.body || {};
  if (!req.user.phone) fail(400, 'Add a phone number to your account first.');
  const origin = text(b.origin, 'departure city and country'); const destination = text(b.destination, 'destination city and country');
  if (routeKey(origin) === routeKey(destination)) fail(400, 'Choose different departure and destination locations.');
  if (!Array.isArray(b.categories) || !b.categories.length || b.categories.some(c => !CATEGORIES.includes(c))) fail(400, 'Choose permitted parcel categories.');
  const data = { organizationId: req.connectOrg, travellerId: req.user.id, origin, destination, departureAt: future(b.departureAt, 'a departure date'),
    flightNumber: text(b.flightNumber, 'airline and flight number'), capacityKg: number(b.capacityKg, 'available baggage capacity', 0.1, 100),
    categories: [...new Set(b.categories)], verificationReference: text(b.verificationReference, 'your identity and ticket verification reference', 500) };
  if (b.complianceAcknowledged !== true) fail(400, 'Confirm that your ticket, baggage allowance and permitted goods require D2F verification.');
  res.status(201).json(await transaction(req, async tx => {
    const trip = await tx.connectTrip.create({ data });
    await audit(tx, req, 'ConnectTrip', trip.id, 'TRIP_SUBMITTED', 'Traveller registration awaiting identity, ticket and compliance review.');
    return safeTrip(trip);
  }));
}));
router.post('/trips/:id/review', requireRole('ADMIN'), wrap(async (req, res) => {
  res.json(await transaction(req, async tx => {
    const t = await getTrip(tx, req);
    if (!['PENDING_REVIEW', 'APPROVED', 'REJECTED'].includes(t.status)) fail(409, 'Departed trips cannot be reconfigured.');
    if (t.assignments.some(a => ACTIVE_ASSIGNMENTS.includes(a.status))) fail(409, 'Remove active assignments before changing trip approval or its receiving location.');
    const status = req.body?.approved === true ? 'APPROVED' : 'REJECTED';
    const reviewNote = text(req.body?.reviewNote, 'verification review notes', 1000);
    let receivingLocationId = null;
    if (status === 'APPROVED') {
      if (t.departureAt <= new Date() || req.body.complianceVerified !== true) fail(400, 'Verify identity, flight, customs eligibility and allowed goods before approval.');
      if (req.body.receivingLocationId) {
        const l = await tx.location.findFirst({ where: { id: req.body.receivingLocationId, organizationId: req.connectOrg } });
        if (!approvedLocationMatches(l, t)) fail(400, 'Choose an approved receiving location in the departure city and country.');
        receivingLocationId = l.id;
      }
      // A verified trip may exist without a hub. Assignment is held for review.
    }
    const trip = await tx.connectTrip.update({ where: { id: t.id }, data: { status, reviewNote, receivingLocationId } });
    await audit(tx, req, 'ConnectTrip', t.id, 'TRIP_REVIEWED', `${status}: ${reviewNote}`);
    return safeTrip(trip);
  }));
}));
router.patch('/trips/:id/finances', requireRole('ADMIN'), wrap(async (req, res) => {
  const compensationMinor = number(req.body?.compensationMinor, 'traveller compensation in cents', 0, 100000000, true);
  const expensesMinor = number(req.body?.expensesMinor, 'operating expenses in cents', 0, 100000000, true);
  res.json(await transaction(req, async tx => { const t = await getTrip(tx, req);
    const updated = await tx.connectTrip.update({ where: { id: t.id }, data: { compensationMinor, expensesMinor } });
    await audit(tx, req, 'ConnectTrip', t.id, 'FINANCES_UPDATED', JSON.stringify({ compensationMinor, expensesMinor })); return safeTrip(updated);
  }));
}));
router.get('/bookings', wrap(async (req, res) => {
  const bookings = await prisma.connectBooking.findMany({ where: { organizationId: req.connectOrg,
    ...(!operations(req.user) ? { parcel: { customer: { userId: req.user.id } } } : {}) }, include: bookingInclude, orderBy: { createdAt: 'desc' } });
  res.json(bookings.map(operations(req.user) ? staffBooking : customerBooking));
}));
router.get('/bookings/:id', wrap(async (req, res) => {
  const b = await getBooking(prisma, req); res.json(operations(req.user) ? staffBooking(b) : customerBooking(b));
}));
router.post('/bookings', requireRole('CUSTOMER'), wrap(async (req, res) => {
  const b = req.body || {};
  if (!req.user.phone) fail(400, 'Add your phone number to your account before booking.');
  const origin = text(b.origin, 'departure city and country'); const destination = text(b.destination, 'destination city and country');
  if (routeKey(origin) === routeKey(destination)) fail(400, 'Choose two different route locations.');
  if (!CATEGORIES.includes(b.category)) fail(400, 'Choose a parcel category.');
  const quantity = number(b.quantity, 'quantity', 1, 99, true); const weightKg = number(b.weightKg, 'total actual weight in kg', 0.001, 100);
  const description = text(b.description, 'the parcel contents', 1000);
  const recipientName = text(b.recipientName, 'recipient name'); const recipientPhone = text(b.recipientPhone, 'recipient phone number', 40);
  if (recipientPhone.length < 6) fail(400, 'Enter the recipient’s full phone number.');
  const recipientAddress = text(b.recipientAddress, 'recipient address', 500);
  const preferredDate = future(b.preferredDate, 'the earliest preferred travel date');
  const declaredValueMinor = number(b.declaredValueMinor, 'declared value in cents', 0, 100000000, true);
  if (!['DOMESTIC_SHIPPING', 'DROP_OFF', 'PICKUP'].includes(b.handoverMode)) fail(400, 'Choose how the parcel reaches D2F.');
  if (!['D2F_PICKUP', 'DELIVERY_REQUEST'].includes(b.deliveryPreference)) fail(400, 'Choose destination pickup or a delivery request.');
  const senderCity = text(b.senderCity, 'your city and state');
  const senderAddress = b.handoverMode === 'DROP_OFF' ? null : text(b.senderAddress, 'your private collection or return address', 500);
  if (b.restrictionsAcknowledged !== true) fail(400, 'Confirm accurate contents and D2F shipping restrictions before booking.');
  const clientRequestId = text(b.clientRequestId, 'a request identifier');
  let created = true;
  const result = await transaction(req, async tx => {
    const existing = await tx.parcel.findUnique({ where: { organizationId_clientRequestId: { organizationId: req.connectOrg, clientRequestId } }, include: { customer: true, connectBooking: true } });
    if (existing) {
      if (existing.customer.userId !== req.user.id || !existing.connectBooking) fail(409, 'Request identifier already used.');
      created = false; return getBooking(tx, req, existing.connectBooking.id);
    }
    let requestedTripId = null;
    if (b.requestedTripId) {
      text(b.requestedTripId, 'the requested trip identifier');
      const t = await tx.connectTrip.findFirst({ where: { id: b.requestedTripId, organizationId: req.connectOrg, status: 'APPROVED' } });
      if (!t || routeKey(t.origin) !== routeKey(origin) || routeKey(t.destination) !== routeKey(destination) || !t.categories.includes(b.category) || t.departureAt < preferredDate) fail(400, 'The requested trip does not match the route, category or preferred date.');
      requestedTripId = t.id;
    }
    const rate = await tx.connectRate.findFirst({ where: { organizationId: req.connectOrg, origin, destination, category: b.category, isActive: true } });
    const internationalFeeMinor = b.category === 'OTHER' || (b.category === 'DOCUMENTS' && weightKg > 0.5) ? null : quote(rate, { weightKg, quantity });
    const customer = await tx.customer.upsert({ where: { userId: req.user.id },
      update: { organizationId: req.connectOrg, displayName: req.user.fullName, email: req.user.email, phone: req.user.phone },
      create: { organizationId: req.connectOrg, userId: req.user.id, displayName: req.user.fullName, email: req.user.email, phone: req.user.phone } });
    const tracking = await generateTrackingId(tx, req.connectOrg);
    const parcel = await tx.parcel.create({ data: { ...tracking, customerId: customer.id, createdById: req.user.id, clientRequestId,
      recipientName, recipientPhone, recipientAddress, packageType: b.category === 'DOCUMENTS' ? 'DOCUMENTS' : 'BOX', weightKg,
      origin, destination, method: 'AIR', serviceType: 'AIR_TRAVELLER', notes: description, status: 'REQUESTED',
      deliveryMode: b.handoverMode === 'PICKUP' ? 'PICKUP' : 'DROP_OFF', restrictionsAcknowledgedAt: new Date(),
      items: { create: { name: description.slice(0, 120), details: description, quantity, weightKg, type: b.category === 'DOCUMENTS' ? 'DOCUMENTS' : 'BOX' } } } });
    const booking = await tx.connectBooking.create({ data: { organizationId: req.connectOrg, parcelId: parcel.id, category: b.category, quantity,
      declaredValueMinor, preferredDate, requestedTripId, handoverMode: b.handoverMode, senderCity, senderAddress, deliveryPreference: b.deliveryPreference,
      domesticStatus: b.handoverMode === 'DOMESTIC_SHIPPING' ? 'AWAITING_ADMIN_REVIEW' : 'NOT_REQUIRED',
      domesticCostMinor: b.handoverMode === 'DOMESTIC_SHIPPING' ? null : 0,
      internationalFeeMinor, pricingSnapshot: rate && internationalFeeMinor != null ? { rateId: rate.id, unit: rate.unit, amountMinor: rate.amountMinor, weightKg, quantity, quotedAt: new Date().toISOString() } : undefined } });
    await tx.trackingIndex.create({ data: { trackingId: tracking.trackingId, parcelId: parcel.id } });
    await event(tx, req, { ...booking, parcel }, 'REQUESTED', 'D2F Connect booking submitted. Awaiting parcel review, traveller acceptance and D2F confirmation.');
    return getBooking(tx, req, booking.id);
  });
  res.status(created ? 201 : 200).json(customerBooking(result));
}));
router.get('/bookings/:id/matches', requireRole('STAFF', 'ADMIN'), wrap(async (req, res) => {
  const b = await getBooking(prisma, req);
  const trips = await prisma.connectTrip.findMany({ where: { organizationId: req.connectOrg, status: 'APPROVED' }, include: tripInclude });
  res.json(trips.filter(t => t.travellerId !== b.parcel.customer.userId && !matchingError(t, b, remaining(t))).map(t => ({ ...safeTrip(t), remainingKg: remaining(t), requiresReceivingLocationReview: !approvedLocationMatches(t.receivingLocation, t) })));
}));
router.post('/bookings/:id/review', requireRole('STAFF', 'ADMIN'), wrap(async (req, res) => {
  res.json(await transaction(req, async tx => {
    const b = await getBooking(tx, req); editable(b);
    const note = text(req.body?.note, 'the contents and compliance review', 1000);
    const verifiedWeightKg = number(req.body?.verifiedWeightKg, 'verified actual weight', 0.001, 100);
    const a = active(b);
    if (a) {
      const trip = await tx.connectTrip.findUnique({ where: { id: a.tripId }, include: tripInclude });
      if (verifiedWeightKg > remaining(trip) + effectiveWeight(b) + 0.00001) fail(409, 'The verified weight exceeds the assigned trip capacity. Remove the assignment first.');
    }
    if (req.body?.approved !== true) {
      await tx.connectAssignment.updateMany({ where: { bookingId: b.id, status: { in: ACTIVE_ASSIGNMENTS } }, data: { status: 'CANCELLED', responseNote: note } });
      await event(tx, req, b, 'REJECTED', note);
    } else {
      await tx.connectBooking.update({ where: { id: b.id }, data: { verifiedWeightKg, contentsVerifiedAt: new Date(), contentsVerificationNote: note } });
      await audit(tx, req, 'ConnectBooking', b.id, 'CONTENTS_VERIFIED', JSON.stringify({ previousWeightKg: b.verifiedWeightKg, verifiedWeightKg, note }));
      await event(tx, req, b, 'UNDER_REVIEW', 'D2F verified the declared contents, compliance and actual weight.', !a && !b.payment && !b.originReceivedAt);
    }
    return staffBooking(await getBooking(tx, req));
  }));
}));
router.post('/bookings/:id/quote', requireRole('ADMIN'), wrap(async (req, res) => {
  res.json(await transaction(req, async tx => { const b = await getBooking(tx, req); editable(b);
    if (b.quoteAcceptedAt || b.payment) fail(409, 'The agreed price is locked. Record an audited exception separately.');
    const internationalFeeMinor = number(req.body?.internationalFeeMinor, 'international fee in cents', 0, 100000000, true);
    const domesticCostMinor = b.handoverMode === 'DOMESTIC_SHIPPING' ? number(req.body?.domesticCostMinor, 'domestic shipping cost in cents', 0, 100000000, true) : 0;
    const note = text(req.body?.note, 'quotation notes', 1000);
    await tx.connectBooking.update({ where: { id: b.id }, data: { internationalFeeMinor, domesticCostMinor, pricingSnapshot: { manual: true, internationalFeeMinor, domesticCostMinor, note, quotedAt: new Date().toISOString() } } });
    await event(tx, req, b, 'QUOTED', 'A D2F quotation is ready for your acceptance.', false); return staffBooking(await getBooking(tx, req));
  }));
}));
router.post('/bookings/:id/accept-quote', requireRole('CUSTOMER'), wrap(async (req, res) => {
  res.json(await transaction(req, async tx => { const b = await getBooking(tx, req); editable(b);
    if (b.internationalFeeMinor == null || b.domesticCostMinor == null) fail(409, 'D2F must complete both shipping fees before you accept.');
    if (req.body?.totalMinor !== b.internationalFeeMinor + b.domesticCostMinor) fail(409, 'The quotation changed. Review the current fees before accepting.');
    if (!b.quoteAcceptedAt) { await tx.connectBooking.update({ where: { id: b.id }, data: { quoteAcceptedAt: new Date() } });
      await event(tx, req, b, 'QUOTE_ACCEPTED', 'Customer accepted the international and domestic fee snapshot.', false); }
    return customerBooking(await getBooking(tx, req));
  }));
}));
router.post('/bookings/:id/assign', requireRole('STAFF', 'ADMIN'), wrap(async (req, res) => {
  res.json(await transaction(req, async tx => { const b = await getBooking(tx, req); editable(b);
    if (!b.contentsVerifiedAt) fail(409, 'Review and approve the parcel contents first.');
    if (active(b)) fail(409, 'This booking already has an active assignment.');
    const t = await tx.connectTrip.findFirst({ where: { id: text(req.body?.tripId, 'the selected trip identifier'), organizationId: req.connectOrg }, include: tripInclude });
    if (!t) fail(404, 'Traveller trip not found.');
    if (t.travellerId === b.parcel.customer.userId) fail(400, 'A traveller cannot be assigned their own booking.');
    const error = matchingError(t, b, remaining(t)); if (error) fail(409, error);
    if (!approvedLocationMatches(t.receivingLocation, t)) fail(409, 'Admin review required: no approved receiving location is available near this traveller.');
    if (b.domesticTrackingNumber && b.receivingLocationId !== t.receivingLocationId) fail(409, 'Domestic shipping is already routed to another receiving location. Admin must reconcile the domestic shipment before reassignment.');
    await tx.connectAssignment.create({ data: { bookingId: b.id, tripId: t.id } });
    await tx.connectBooking.update({ where: { id: b.id }, data: { receivingLocationId: t.receivingLocationId } });
    await event(tx, req, b, 'TRAVELLER_PROPOSED', 'D2F proposed a verified traveller. Traveller acceptance is pending.'); return staffBooking(await getBooking(tx, req));
  }));
}));
router.post('/assignments/:id/respond', requireRole('CUSTOMER'), wrap(async (req, res) => {
  res.json(await transaction(req, async tx => {
    const a = await tx.connectAssignment.findFirst({ where: { id: req.params.id, trip: { organizationId: req.connectOrg, travellerId: req.user.id } }, include: { trip: true, booking: { include: bookingInclude } } });
    if (!a) fail(404, 'Assignment not found.');
    if (a.booking.collectedAt || a.trip.status !== 'APPROVED') fail(409, 'This parcel cannot be accepted or rejected at this stage. Contact D2F.');
    if (!['PROPOSED', 'ACCEPTED', 'CONFIRMED'].includes(a.status)) fail(409, 'This assignment is no longer available.');
    const accepted = req.body?.accepted;
    if (typeof accepted !== 'boolean') fail(400, 'Accept or decline the proposed parcel.');
    if (accepted && a.status !== 'PROPOSED') fail(409, 'This assignment has already been reviewed.');
    const responseNote = text(req.body?.note, accepted ? 'your contents acceptance note' : 'the reason you cannot transport these contents', 500);
    await tx.connectAssignment.update({ where: { id: a.id }, data: { status: accepted ? 'ACCEPTED' : 'DECLINED', responseNote, acceptedAt: accepted ? new Date() : null } });
    if (!accepted) await tx.connectBooking.update({ where: { id: a.bookingId }, data: { handoverCodeHash: null, handoverCodeExpiresAt: null } });
    await event(tx, req, a.booking, accepted ? 'TRAVELLER_ACCEPTED' : 'UNDER_REVIEW', accepted ? 'Traveller accepted the proposed parcel. D2F final confirmation is pending.' : 'Traveller declined the contents. D2F is reviewing the booking.');
    return { id: a.id, status: accepted ? 'ACCEPTED' : 'DECLINED' };
  }));
}));
router.post('/bookings/:id/confirm-assignment', requireRole('STAFF', 'ADMIN'), wrap(async (req, res) => {
  res.json(await transaction(req, async tx => { const b = await getBooking(tx, req); editable(b); const a = active(b);
    if (!a || a.status !== 'ACCEPTED') fail(409, 'The traveller must accept before D2F confirms the assignment.');
    if (!b.contentsVerifiedAt) fail(409, 'D2F contents verification is required.');
    if (a.trip.status !== 'APPROVED' || !approvedLocationMatches(b.receivingLocation, a.trip)) fail(409, 'The approved trip and receiving location must remain valid before final confirmation.');
    await tx.connectAssignment.update({ where: { id: a.id }, data: { status: 'CONFIRMED', confirmedAt: new Date() } });
    await event(tx, req, b, 'TRAVELLER_ASSIGNED', 'D2F confirmed the traveller assignment.'); return staffBooking(await getBooking(tx, req));
  }));
}));
router.post('/bookings/:id/unassign', requireRole('STAFF', 'ADMIN'), wrap(async (req, res) => {
  res.json(await transaction(req, async tx => { const b = await getBooking(tx, req); editable(b); const a = active(b);
    if (!a) fail(409, 'There is no active assignment.');
    const note = text(req.body?.note, 'the reassignment reason', 1000);
    await tx.connectAssignment.update({ where: { id: a.id }, data: { status: 'CANCELLED', responseNote: note } });
    await tx.connectBooking.update({ where: { id: b.id }, data: { handoverCodeHash: null, handoverCodeExpiresAt: null } });
    await event(tx, req, b, 'UNDER_REVIEW', `D2F removed the assignment: ${note}`); return staffBooking(await getBooking(tx, req));
  }));
}));
router.post('/bookings/:id/payment-instructions', requireRole('ADMIN'), wrap(async (req, res) => {
  res.json(await transaction(req, async tx => {
    const b = await getBooking(tx, req); editable(b);
    if (b.payment) fail(409, 'Payment was already confirmed.');
    const paymentInstructions = text(req.body?.instructions, 'verified D2F payment instructions', 1000);
    await tx.connectBooking.update({ where: { id: b.id }, data: { paymentInstructions } });
    await event(tx, req, b, 'PAYMENT_INSTRUCTIONS', 'D2F provided payment instructions for this booking.', false);
    return staffBooking(await getBooking(tx, req));
  }));
}));
router.post('/bookings/:id/exception-review', requireRole('ADMIN'), wrap(async (req, res) => {
  res.json(await transaction(req, async tx => {
    const b = await getBooking(tx, req);
    const note = text(req.body?.note, 'the operational exception and approved correction plan', 1000);
    await audit(tx, req, 'ConnectBooking', b.id, 'EXCEPTION_REVIEW', note);
    await tx.trackingEvent.create({ data: { parcelId: b.parcelId, status: b.parcel.status, actorId: req.user.id, note: 'D2F recorded an operational exception for review. Existing confirmed handovers remain recorded.' } });
    return staffBooking(await getBooking(tx, req));
  }));
}));
router.post('/bookings/:id/payment', requireRole('ADMIN'), wrap(async (req, res) => {
  res.json(await transaction(req, async tx => { const b = await getBooking(tx, req); editable(b);
    if (!b.quoteAcceptedAt) fail(409, 'The customer must accept the completed quotation first.');
    const reference = text(req.body?.reference, 'the unique payment reference');
    const amountMinor = number(req.body?.amountMinor, 'the paid amount in cents', 0, 200000000, true);
    if (amountMinor !== b.internationalFeeMinor + b.domesticCostMinor) fail(400, 'Payment must match the accepted total quotation.');
    if (b.payment) { if (b.payment.reference !== reference || b.payment.amountMinor !== amountMinor) fail(409, 'Payment has already been recorded for this booking.'); return staffBooking(b); }
    if (await tx.connectPayment.findUnique({ where: { organizationId_reference: { organizationId: req.connectOrg, reference } } })) fail(409, 'This payment reference was already recorded.');
    await tx.connectPayment.create({ data: { organizationId: req.connectOrg, bookingId: b.id, reference, amountMinor, recordedById: req.user.id } });
    await event(tx, req, b, 'PAYMENT_CONFIRMED', 'D2F confirmed payment of the accepted domestic and international fees.'); return staffBooking(await getBooking(tx, req));
  }));
}));
router.post('/bookings/:id/domestic', requireRole('STAFF', 'ADMIN'), wrap(async (req, res) => {
  res.json(await transaction(req, async tx => { const b = await getBooking(tx, req); editable(b);
    if (b.handoverMode !== 'DOMESTIC_SHIPPING' || b.originReceivedAt) fail(409, 'This booking does not need a domestic shipping label.');
    if (!b.payment || active(b)?.status !== 'CONFIRMED' || !approvedLocationMatches(b.receivingLocation, active(b).trip)) fail(409, 'Payment, confirmed assignment and an approved receiving location are required first.');
    const domesticCarrier = text(req.body?.carrier, 'domestic carrier', 60); const domesticTrackingNumber = text(req.body?.trackingNumber, 'domestic tracking number');
    const domesticLabelUrl = text(req.body?.labelUrl, 'the domestic shipping label link', 1000);
    let url; try { url = new URL(domesticLabelUrl); } catch { fail(400, 'Use a valid HTTPS label link.'); }
    if (url.protocol !== 'https:' || url.username || url.password) fail(400, 'Use a secure HTTPS label link.');
    await tx.connectBooking.update({ where: { id: b.id }, data: { domesticCarrier, domesticTrackingNumber, domesticLabelUrl, domesticStatus: 'LABEL_READY' } });
    await event(tx, req, b, 'DOMESTIC_LABEL_READY', 'D2F prepared a domestic label to the approved receiving location.', false); return staffBooking(await getBooking(tx, req));
  }));
}));
router.post('/bookings/:id/domestic-dispatched', wrap(async (req, res) => {
  res.json(await transaction(req, async tx => { const b = await getBooking(tx, req); editable(b);
    if (b.domesticStatus !== 'LABEL_READY' || !b.domesticTrackingNumber) fail(409, 'D2F must provide the domestic label before dispatch.');
    await tx.connectBooking.update({ where: { id: b.id }, data: { domesticStatus: 'IN_TRANSIT' } });
    await event(tx, req, b, 'DOMESTIC_IN_TRANSIT', 'Customer confirmed domestic carrier dispatch to the D2F receiving location.'); return operations(req.user) ? staffBooking(await getBooking(tx, req)) : customerBooking(await getBooking(tx, req));
  }));
}));
router.post('/bookings/:id/receive', requireRole('STAFF', 'ADMIN'), wrap(async (req, res) => {
  res.json(await transaction(req, async tx => { const b = await getBooking(tx, req); editable(b); facility(req, b.receivingLocation);
    if (b.originReceivedAt) fail(409, 'The receiving location already confirmed this parcel.');
    if (!b.contentsVerifiedAt || active(b)?.status !== 'CONFIRMED' || !b.payment || !approvedLocationMatches(b.receivingLocation, active(b).trip)) fail(409, 'Verified contents, traveller confirmation and payment are required before intake.');
    if (b.handoverMode === 'DOMESTIC_SHIPPING' && !['LABEL_READY', 'IN_TRANSIT'].includes(b.domesticStatus)) fail(409, 'Record the domestic label and carrier tracking first.');
    const note = text(req.body?.note, 'the receiving inspection and package condition', 1000);
    await tx.connectBooking.update({ where: { id: b.id }, data: { originReceivedAt: new Date(), domesticStatus: b.handoverMode === 'DOMESTIC_SHIPPING' ? 'RECEIVED' : 'NOT_REQUIRED' } });
    await tx.parcel.update({ where: { id: b.parcelId }, data: { locationId: b.receivingLocationId } });
    await event(tx, req, b, 'RECEIVED_BY_D2F', `Approved receiving location confirmed the parcel: ${note}`); return staffBooking(await getBooking(tx, req));
  }));
}));
router.post('/bookings/:id/authorize-handover', requireRole('STAFF', 'ADMIN'), wrap(async (req, res) => {
  res.json(await transaction(req, async tx => { const b = await getBooking(tx, req); editable(b); facility(req, b.receivingLocation);
    if (!b.originReceivedAt || !b.contentsVerifiedAt || !b.payment || active(b)?.status !== 'CONFIRMED' || !approvedLocationMatches(b.receivingLocation, active(b).trip)) fail(409, 'D2F intake, contents approval, payment and assignment confirmation are required.');
    const code = randomInt(0, 1000000).toString().padStart(6, '0');
    const expiresAt = new Date(Date.now() + 10 * 60000);
    await tx.connectBooking.update({ where: { id: b.id }, data: { handoverCodeHash: createHash('sha256').update(`${b.id}:${code}`).digest('hex'), handoverCodeExpiresAt: expiresAt, handoverAttempts: 0 } });
    await event(tx, req, b, 'HANDOVER_AUTHORIZED', 'D2F authorized traveller collection at the approved receiving location.');
    return { code, expiresAt, trackingId: b.parcel.trackingId };
  }));
}));
router.post('/assignments/:id/collect', requireRole('CUSTOMER'), wrap(async (req, res) => {
  const result = await transaction(req, async tx => {
    const a = await tx.connectAssignment.findFirst({ where: { id: req.params.id, status: 'CONFIRMED', trip: { organizationId: req.connectOrg, travellerId: req.user.id, status: 'APPROVED' } }, include: { booking: { include: bookingInclude } } });
    if (!a) fail(404, 'Confirmed traveller assignment not found.');
    const b = a.booking;
    if (!b.originReceivedAt || !b.contentsVerifiedAt || !b.payment || !approvedLocationMatches(b.receivingLocation, active(b)?.trip)) fail(409, 'D2F must confirm the approved receiving location, contents, intake and payment before collection.');
    if (b.collectedAt || !b.handoverCodeHash || !b.handoverCodeExpiresAt || b.handoverCodeExpiresAt < new Date() || b.handoverAttempts >= 5) fail(409, 'Ask the D2F receiving team for a new collection code.');
    if (req.body?.contentsAccepted !== true) fail(400, 'Verify the contents and confirm they are safe and permitted before collection.');
    const candidate = createHash('sha256').update(`${b.id}:${String(req.body?.code || '')}`).digest();
    if (!timingSafeEqual(candidate, Buffer.from(b.handoverCodeHash, 'hex'))) {
      await tx.connectBooking.update({ where: { id: b.id }, data: { handoverAttempts: { increment: 1 } } });
      await audit(tx, req, 'ConnectBooking', b.id, 'COLLECTION_CODE_REJECTED', 'Invalid single-use collection code.');
      return { invalidCode: true };
    }
    await tx.connectBooking.update({ where: { id: b.id }, data: { collectedAt: new Date(), handoverCodeHash: null, handoverCodeExpiresAt: null } });
    await event(tx, req, b, 'HANDED_TO_TRAVELLER', 'Assigned traveller verified the contents and confirmed collection using a single-use D2F code.');
    return { collected: true, trackingId: b.parcel.trackingId };
  });
  if (result.invalidCode) return res.status(400).json({ error: 'Incorrect collection code. Ask the receiving team to verify it.' });
  res.json(result);
}));
router.post('/trips/:id/depart', requireRole('STAFF', 'ADMIN'), wrap(async (req, res) => {
  res.json(await transaction(req, async tx => { const t = await getTrip(tx, req); facility(req, t.receivingLocation);
    if (t.status !== 'APPROVED') fail(409, 'Only an approved trip may depart.');
    const assignments = t.assignments.filter(a => ACTIVE_ASSIGNMENTS.includes(a.status));
    if (!assignments.length || assignments.some(a => a.status !== 'CONFIRMED' || !a.booking.collectedAt)) fail(409, 'Every active assignment must be confirmed and physically collected before departure.');
    if (req.body?.confirmed !== true) fail(400, 'Confirm the traveller’s actual departure.');
    await tx.connectTrip.update({ where: { id: t.id }, data: { status: 'DEPARTED' } });
    for (const a of assignments) await event(tx, req, a.booking, 'TRAVELLER_DEPARTED', 'D2F confirmed the traveller’s actual departure.');
    await audit(tx, req, 'ConnectTrip', t.id, 'TRIP_DEPARTED', 'Manifest frozen at departure.'); return { departed: true };
  }));
}));
router.get('/trips/:id/manifest', wrap(async (req, res) => {
  const t = await getTrip(prisma, req);
  res.json({ trip: safeTrip(t), remainingKg: remaining(t), parcels: t.assignments.filter(a => a.status === 'CONFIRMED').map(travellerAssignment) });
}));
router.post('/bookings/:id/destination-received', requireRole('STAFF', 'ADMIN'), wrap(async (req, res) => {
  res.json(await transaction(req, async tx => { const b = await getBooking(tx, req); const a = active(b);
    if (!b.collectedAt || a?.trip.status !== 'DEPARTED' || b.destinationReceivedAt) fail(409, 'Confirm traveller departure before recording destination receipt once.');
    const l = await tx.location.findFirst({ where: { id: text(req.body?.locationId, 'the receiving location identifier'), organizationId: req.connectOrg } }); facility(req, l);
    if (!approvedLocationMatches(l, { origin: b.parcel.destination })) fail(400, 'Select an approved receiving team at this booking’s destination.');
    const note = text(req.body?.note, 'destination handover and condition notes', 1000);
    await tx.connectBooking.update({ where: { id: b.id }, data: { destinationReceivedAt: new Date() } });
    await tx.parcel.update({ where: { id: b.parcelId }, data: { locationId: l.id } });
    await event(tx, req, b, 'ARRIVED_DESTINATION', `Approved destination team received the parcel: ${note}`); return staffBooking(await getBooking(tx, req));
  }));
}));
router.post('/bookings/:id/ready', requireRole('STAFF', 'ADMIN'), wrap(async (req, res) => {
  res.json(await transaction(req, async tx => { const b = await getBooking(tx, req);
    if (!b.destinationReceivedAt || b.parcel.status !== 'ARRIVED_DESTINATION') fail(409, 'The destination team must receive the parcel before making it ready.');
    facility(req, await tx.location.findUnique({ where: { id: b.parcel.locationId } }));
    await event(tx, req, b, 'READY_FOR_PICKUP', 'The receiving team confirmed the parcel is ready for recipient handover.'); return staffBooking(await getBooking(tx, req));
  }));
}));
router.post('/bookings/:id/deliver', requireRole('STAFF', 'ADMIN'), wrap(async (req, res) => {
  res.json(await transaction(req, async tx => { const b = await getBooking(tx, req);
    if (!b.destinationReceivedAt || b.parcel.status !== 'READY_FOR_PICKUP' || b.deliveredAt) fail(409, 'Confirm destination receipt and readiness before delivery.');
    facility(req, await tx.location.findUnique({ where: { id: b.parcel.locationId } }));
    const recipientName = text(req.body?.recipientName, 'the verified recipient name');
    const evidence = text(req.body?.evidence, 'the identity check and delivery proof reference', 1000);
    if (req.body?.confirmed !== true) fail(400, 'Confirm that the actual recipient handover took place.');
    const deliveredAt = new Date();
    await tx.connectBooking.update({ where: { id: b.id }, data: { deliveredAt, deliveryEvidence: `${recipientName}: ${evidence}` } });
    await tx.parcel.update({ where: { id: b.parcelId }, data: { deliveredAt, deliveredToName: recipientName, deliveryProofType: 'ID_CONFIRMATION', deliveryProofReference: evidence } });
    await event(tx, req, b, 'DELIVERED', 'D2F verified the recipient and recorded the actual delivery handover.'); return staffBooking(await getBooking(tx, req));
  }));
}));
export default router;
