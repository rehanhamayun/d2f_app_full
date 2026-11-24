import directoryRouter from './operations_directory.js';
import { Router } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { resolveOrganizationId } from '../tracking.js';
import { warehouseLock, fail, locationLabel, containerInclude, manifestFor, containerAudit } from '../warehouse.js';
import { SERVICE_COUNTRIES, COUNTRY_TIMEZONES, countryInLocation } from '../service_area.js';
import { isFacilityAuthorized, facilityDeniedMessage, destinationMatchesLocation } from '../parcel_rules.js';
const router = Router();
router.use(authenticate, requireRole('STAFF', 'ADMIN'), async (req, res, next) => {
  try { req.organizationId = await resolveOrganizationId(prisma, req.user); next(); } catch (e) { next(e); }
});
router.use('/directory', directoryRouter);
const text = (v, max = 120) => typeof v === 'string' && v.trim().length > 0 && v.trim().length <= max;
router.get('/locations', async (req, res, next) => {
  try { res.json(await prisma.location.findMany({ where: { organizationId: req.organizationId }, orderBy: { name: 'asc' } })); } catch (e) { next(e); }
});
async function saveLocation(req, res, next) {
  try {
    const { name, code, city, country, timezone } = req.body || {};
    if (!text(name) || !text(code, 20) || !/^[A-Z0-9-]+$/i.test(code.trim()) || !text(city) || !SERVICE_COUNTRIES.includes(country)) fail(400, 'Enter a name, location code, city and supported service country.');
    const selectedTimezone = timezone || COUNTRY_TIMEZONES[country];
    try { if (typeof selectedTimezone !== 'string') throw new Error(); new Intl.DateTimeFormat('en', { timeZone: selectedTimezone }); } catch { fail(400, 'Enter a valid IANA time zone, for example America/Chicago.'); }
    const data = { name: name.trim(), code: code.trim().toUpperCase(), city: city.trim(), country, timezone: selectedTimezone };
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      if (req.params.id) {
        const existing = await tx.location.findFirst({ where: { id: req.params.id, organizationId: req.organizationId } });
        if (!existing) fail(404, 'Location not found.');
        if (await tx.container.count({ where: { OR: [{ originId: existing.id }, { destinationId: existing.id }] } })) fail(409, 'This location is used by a container. Create a new location to preserve shipping records.');
      }
      const location = req.params.id
        ? await tx.location.update({ where: { id: req.params.id }, data })
        : await tx.location.create({ data: { ...data, organizationId: req.organizationId } });
      await tx.auditLog.create({ data: { actorId: req.user.id, action: req.params.id ? 'LOCATION_UPDATE' : 'LOCATION_CREATE', entity: 'Location', entityId: location.id, detail: `${location.code}: ${location.name}` } });
      return location;
    });
    res.status(req.params.id ? 200 : 201).json(result);
  } catch (e) { if (e.code === 'P2002') return res.status(409).json({ error: 'This location code already exists.' }); next(e); }
}
router.post('/locations', requireRole('ADMIN'), saveLocation);
router.patch('/locations/:id', requireRole('ADMIN'), saveLocation);
router.get('/containers', async (req, res, next) => {
  try {
    const limit = Number(req.query.limit ?? 50), offset = Number(req.query.offset ?? 0);
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100 || !Number.isSafeInteger(offset) || offset < 0) fail(400, 'Invalid page.');
    const q = req.query.q?.toString().trim();
    const status = req.query.status?.toString();
    if (status && !['ALL', 'LOADING', 'DEPARTED', 'ARRIVED_PORT', 'CUSTOMS_CLEARANCE', 'CUSTOMS_CLEARED', 'ARRIVED'].includes(status)) fail(400, 'Choose a valid container status.');
    const where = { organizationId: req.organizationId, ...(status && status !== 'ALL' ? { status } : {}), ...(q ? { code: { contains: q, mode: 'insensitive' } } : {}) };
    const [containers, total] = await prisma.$transaction([
      prisma.container.findMany({ where, include: containerInclude, orderBy: [{ createdAt: 'desc' }, { id: 'asc' }], take: limit, skip: offset }), prisma.container.count({ where }),
    ]);
    res.json({ containers, total, limit, offset });
  } catch (e) { next(e); }
});
router.post('/containers', async (req, res, next) => {
  try {
    const { code, originId, destinationId, method = 'SEA', sealNumber, notes, onwardCountries = [] } = req.body || {};
    if (!text(code, 40) || !/^[A-Z0-9-]+$/i.test(code.trim()) || typeof originId !== 'string' || typeof destinationId !== 'string' || originId === destinationId || !['AIR', 'SEA', 'ROAD'].includes(method) || (sealNumber != null && !text(sealNumber, 80)) || (notes != null && !text(notes, 2000))) fail(400, 'Enter a container reference, two different locations and a shipping method.');
    if (!Array.isArray(onwardCountries) || onwardCountries.some(c => !SERVICE_COUNTRIES.includes(c))) fail(400, 'Choose supported onward countries.');
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const locations = await tx.location.findMany({ where: { id: { in: [originId, destinationId] }, organizationId: req.organizationId } });
      if (locations.length !== 2) fail(400, 'Choose locations belonging to your organization.');
      const origin = locations.find(location => location.id === originId);
      const destination = locations.find(location => location.id === destinationId);
      if (onwardCountries.includes(destination.country)) fail(400, 'Choose onward countries beyond the container leg destination.');
      if (!isFacilityAuthorized(req.user, origin)) fail(403, facilityDeniedMessage(origin));
      const container = await tx.container.create({ data: { organizationId: req.organizationId, code: code.trim().toUpperCase(), originId, destinationId, method, onwardCountries: [...new Set(onwardCountries)], sealNumber: sealNumber?.trim() || null, notes: notes?.trim() || null }, include: containerInclude });
      await containerAudit(tx, req.user, container.id, 'CREATED', 'Container opened for loading');
      return container;
    });
    res.status(201).json(result);
  } catch (e) { if (e.code === 'P2002') return res.status(409).json({ error: 'This container reference already exists.' }); next(e); }
});
router.patch('/containers/:id/route', async (req, res, next) => {
  try {
    const { onwardCountries, notes } = req.body || {};
    if (!Array.isArray(onwardCountries) || onwardCountries.some(country => !SERVICE_COUNTRIES.includes(country))) fail(400, 'Choose supported onward countries.');
    if (notes != null && !text(notes, 2000)) fail(400, 'Keep onward instructions under 2,000 characters.');
    const updated = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const container = await tx.container.findFirst({ where: { id: req.params.id, organizationId: req.organizationId }, include: { ...containerInclude, parcels: { select: { destination: true, trackingId: true } } } });
      if (!container) fail(404, 'Container not found.');
      if (container.status !== 'LOADING') fail(409, 'The route is frozen after the container departs.');
      if (!isFacilityAuthorized(req.user, container.origin)) fail(403, facilityDeniedMessage(container.origin));
      if (onwardCountries.includes(container.destination.country)) fail(400, 'Choose onward countries beyond the container leg destination.');
      const invalid = container.parcels.find(parcel => !destinationMatchesLocation(parcel.destination, container.destination) && !onwardCountries.includes(countryInLocation(parcel.destination)));
      if (invalid) fail(409, `Remove ${invalid.trackingId} before removing its onward country.`);
      const countries = [...new Set(onwardCountries)];
      const result = await tx.container.update({ where: { id: container.id }, data: { onwardCountries: countries, notes: notes?.trim() || null }, include: containerInclude });
      await containerAudit(tx, req.user, container.id, 'ROUTE_UPDATED', countries.length ? `Onward to ${countries.join(', ')}` : 'Direct route');
      return result;
    });
    res.json(updated);
  } catch (e) { next(e); }
});
router.get('/containers/:id', async (req, res, next) => {
  try {
    const result = await prisma.container.findFirst({ where: { id: req.params.id, organizationId: req.organizationId }, include: { ...containerInclude,
      parcels: { orderBy: { trackingId: 'asc' }, include: { customer: { select: { id: true, displayName: true } } } }, events: { orderBy: [{ createdAt: 'asc' }, { id: 'asc' }] } } });
    if (!result) fail(404, 'Container not found.');
    res.json(result);
  } catch (e) { next(e); }
});
router.get('/containers/:id/manifest', async (req, res, next) => {
  try {
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const container = await tx.container.findFirst({ where: { id: req.params.id, organizationId: req.organizationId }, include: containerInclude });
      if (!container) fail(404, 'Container not found.');
      return manifestFor(tx, container);
    });
    res.json(result);
  } catch (e) { next(e); }
});
router.post('/containers/:id/parcels', async (req, res, next) => {
  try {
    const trackingId = req.body?.trackingId;
    if (req.body?.loadingConfirmed !== true) fail(400, 'Confirm that every warehouse-verified package in this shipment has physically been loaded.');
    if (!text(trackingId, 80)) fail(400, 'Scan or enter a tracking number.');
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const container = await tx.container.findFirst({ where: { id: req.params.id, organizationId: req.organizationId }, include: containerInclude });
      if (!container) fail(404, 'Container not found.');
      if (container.status !== 'LOADING') fail(409, 'Loading is closed for this container.');
      if (!isFacilityAuthorized(req.user, container.origin)) fail(403, facilityDeniedMessage(container.origin));
      const parcel = await tx.parcel.findFirst({ where: { trackingId: trackingId.trim().toUpperCase(), organizationId: req.organizationId } });
      if (!parcel) fail(404, 'Parcel not found.');
      if (parcel.serviceType === 'AIR_TRAVELLER') fail(409, 'D2F Connect parcels use a traveller manifest, not a cargo container.');
      if (parcel.containerId === container.id) return { parcel, alreadyLoaded: true };
      if (parcel.containerId) fail(409, 'This parcel is already assigned to another container.');
      if (!(parcel.method === 'SEA' ? ['READY_FOR_LOADING'] : ['RECEIVED', 'PROCESSING']).includes(parcel.status)) fail(409, 'Complete processing and mark sea parcels Ready for Loading before loading.');
      const packages = await tx.parcelItem.findMany({ where: { parcelId: parcel.id, notCollectedReason: null } });
      if (packages.some(p => !p.warehouseReceivedAt)) fail(409, 'All collected packages require warehouse verification before loading.');
      if (!parcel.warehouseReceivedAt) fail(409, 'Warehouse staff must scan and verify receipt before container loading.');
      if (!destinationMatchesLocation(parcel.destination, container.destination) && !container.onwardCountries.includes(countryInLocation(parcel.destination))) fail(409, 'This parcel destination is outside the container route. Choose a direct container or one with the correct onward transfer.');
      if (parcel.locationId !== container.originId) fail(409, 'The parcel must be received at the container origin before it can be loaded.');
      const parcelOriginCountry = countryInLocation(parcel.origin);
      if (parcelOriginCountry && parcelOriginCountry !== container.origin.country) fail(409, 'Parcel origin does not match the container origin country.');
      if (parcel.method !== container.method) fail(409, 'Parcel and container shipping methods must match.');
      // Loading is the physical processing step, so a received parcel moves to
      // PROCESSING before the container can depart. This preserves the strict
      // RECEIVED → PROCESSING → IN_TRANSIT lifecycle.
      const nextStatus = parcel.method === 'SEA' ? 'LOADED_IN_CONTAINER' : parcel.status === 'RECEIVED' ? 'PROCESSING' : parcel.status;
      const updated = await tx.parcel.update({
        where: { id: parcel.id },
        data: { containerId: container.id, status: nextStatus, locationId: container.originId },
      });
      await tx.trackingEvent.create({ data: { parcelId: parcel.id, status: nextStatus, actorId: req.user.id, facilityId: container.originId, location: locationLabel(container.origin), note: `Loaded into container ${container.code}` } });
      await containerAudit(tx, req.user, container.id, 'PARCEL_LOADED', parcel.trackingId);
      return { parcel: updated, alreadyLoaded: false };
    });
    res.status(result.alreadyLoaded ? 200 : 201).json(result);
  } catch (e) { next(e); }
});
router.delete('/containers/:id/parcels/:parcelId', async (req, res, next) => {
  try {
    await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const container = await tx.container.findFirst({ where: { id: req.params.id, organizationId: req.organizationId }, include: containerInclude });
      if (!container) fail(404, 'Container not found.');
      if (container.status !== 'LOADING') fail(409, 'Parcels cannot be removed after departure.');
      if (!isFacilityAuthorized(req.user, container.origin)) fail(403, facilityDeniedMessage(container.origin));
      const parcel = await tx.parcel.findFirst({ where: { id: req.params.parcelId, containerId: container.id, organizationId: req.organizationId } });
      if (!parcel) fail(404, 'Loaded parcel not found.');
      await tx.parcel.update({ where: { id: parcel.id }, data: { containerId: null, ...(parcel.method === 'SEA' ? { status: 'READY_FOR_LOADING' } : {}) } });
      await tx.trackingEvent.create({ data: { parcelId: parcel.id, status: parcel.method === 'SEA' ? 'READY_FOR_LOADING' : parcel.status, actorId: req.user.id, facilityId: container.originId, location: locationLabel(container.origin), note: `Removed from container ${container.code}` } });
      await containerAudit(tx, req.user, container.id, 'PARCEL_REMOVED', parcel.trackingId);
    });
    res.json({ ok: true });
  } catch (e) { next(e); }
});
router.post('/containers/:id/events', async (req, res, next) => {
  try {
    let { action } = req.body || {};
    if (!['DEPARTED', 'ARRIVED_PORT', 'CUSTOMS_CLEARANCE', 'CUSTOMS_CLEARED', 'ARRIVED'].includes(action)) fail(400, 'Choose a valid physical container event.');
    if (req.body?.confirmed !== true) fail(400, 'Confirm the actual physical container event before continuing.');
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const container = await tx.container.findFirst({ where: { id: req.params.id, organizationId: req.organizationId }, include: { ...containerInclude, parcels: true } });
      if (!container) fail(404, 'Container not found.');
      // Older clients call their single arrival action ARRIVED. For sea this
      // records port arrival only, never customs release or warehouse receipt.
      if (container.method === 'SEA' && container.status === 'DEPARTED' && action === 'ARRIVED') action = 'ARRIVED_PORT';
      const sequence = container.method === 'SEA'
        ? { LOADING: 'DEPARTED', DEPARTED: 'ARRIVED_PORT', ARRIVED_PORT: 'CUSTOMS_CLEARANCE', CUSTOMS_CLEARANCE: 'CUSTOMS_CLEARED', CUSTOMS_CLEARED: 'ARRIVED' }
        : { LOADING: 'DEPARTED', DEPARTED: 'ARRIVED' };
      if (sequence[container.status] !== action) fail(409, 'Follow confirmed departure, port arrival, customs clearance and destination warehouse receipt in order. Refresh this container.');
      const eventFacility = action === 'DEPARTED' ? container.origin : container.destination;
      if (!isFacilityAuthorized(req.user, eventFacility)) fail(403, facilityDeniedMessage(eventFacility));
      if (!container.parcels.length) fail(409, 'Load at least one parcel before departure.');
      const departing = action === 'DEPARTED';
      const expected = departing ? (container.method === 'SEA' ? ['LOADED_IN_CONTAINER'] : ['RECEIVED', 'PROCESSING'])
        : { DEPARTED: ['IN_TRANSIT'], ARRIVED_PORT: ['ARRIVED_PORT'], CUSTOMS_CLEARANCE: ['CUSTOMS_CLEARANCE'], CUSTOMS_CLEARED: ['CUSTOMS_CLEARED'] }[container.status];
      const incompatible = container.parcels.find(p => !expected.includes(p.status) &&
        !(departing && container.method === 'SEA' && ['RECEIVED', 'PROCESSING', 'READY_FOR_LOADING'].includes(p.status)
          && p.warehouseReceivedAt && p.locationId === container.originId));
      if (incompatible) fail(409, `Parcel ${incompatible.trackingId} is ${incompatible.status.replaceAll('_', ' ').toLowerCase()}. Verify its loaded status before confirming this event.`);
      const location = locationLabel(eventFacility);
      const labels = { DEPARTED: 'Departure confirmed', ARRIVED_PORT: 'Destination port arrival confirmed', CUSTOMS_CLEARANCE: 'Customs clearance started', CUSTOMS_CLEARED: 'Customs release confirmed', ARRIVED: 'Destination warehouse receipt confirmed' };
      const note = `${labels[action]} · ${location} · Container ${container.code}`;
      const status = departing ? 'IN_TRANSIT' : container.method === 'SEA'
        ? { ARRIVED_PORT: 'ARRIVED_PORT', CUSTOMS_CLEARANCE: 'CUSTOMS_CLEARANCE', CUSTOMS_CLEARED: 'CUSTOMS_CLEARED', ARRIVED: 'RECEIVED_DESTINATION' }[action]
        : (container.destination.country === 'Togo' ? 'ARRIVED_LOME' : 'ARRIVED_DESTINATION');
      const manifest = departing ? await manifestFor(tx, container) : undefined;
      if (manifest) manifest.provisional = false;
      const onward = action === 'ARRIVED'
        ? container.parcels.filter(p => container.onwardCountries.includes(countryInLocation(p.destination)))
        : [];
      const onwardIds = new Set(onward.map(p => p.id));
      await tx.parcel.updateMany({ where: { containerId: container.id, id: { notIn: [...onwardIds] } }, data: { status, locationId: eventFacility.id } });
      if (onward.length) await tx.parcel.updateMany({ where: { id: { in: [...onwardIds] } }, data: { status: 'IN_TRANSIT', locationId: eventFacility.id } });
      await tx.trackingEvent.createMany({ data: container.parcels.map(p => {
        const transfer = onwardIds.has(p.id);
        const message = transfer ? `Received at ${location} for onward transfer to ${p.destination}.` : note;
        return { parcelId: p.id, status: transfer ? 'IN_TRANSIT' : status, location, note: message, originalNote: message, facilityId: eventFacility.id, actorId: req.user.id };
      }) });
      await containerAudit(tx, req.user, container.id, action, note);
      return tx.container.update({ where: { id: container.id }, data: { status: action, ...(manifest ? { manifest } : {}) }, include: containerInclude });
    }, { maxWait: 10000, timeout: 30000 });
    res.status(201).json(result);
  } catch (e) { next(e); }
});
router.post('/containers/:id/parcels/:parcelId/onward', async (req, res, next) => {
  try {
    const { action, locationId, confirmed } = req.body || {};
    if (confirmed !== true || !['DISPATCH', 'RECEIVE'].includes(action)) fail(400, 'Confirm the physical onward transfer action.');
    const parcel = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const container = await tx.container.findFirst({ where: { id: req.params.id, organizationId: req.organizationId }, include: containerInclude });
      if (container?.status !== 'ARRIVED') fail(409, 'Confirm the container warehouse receipt before recording onward transfer.');
      const p = await tx.parcel.findFirst({ where: { id: req.params.parcelId, containerId: container.id, organizationId: req.organizationId } });
      if (!p || !container.onwardCountries.includes(countryInLocation(p.destination))) fail(404, 'Parcel is not on this onward route.');
      if (p.status !== 'IN_TRANSIT' || p.locationId !== container.destinationId) fail(409, 'This parcel is no longer awaiting onward transfer. Refresh the record.');
      const dispatching = action === 'DISPATCH';
      if (dispatching === Boolean(p.onwardDispatchedAt)) fail(409, dispatching ? 'Onward dispatch is already recorded.' : 'Record onward dispatch before confirming receipt.');
      const facility = dispatching ? container.destination : await tx.location.findFirst({ where: { id: typeof locationId === 'string' ? locationId : '', organizationId: req.organizationId } });
      if (!facility || (!dispatching && !destinationMatchesLocation(p.destination, facility))) fail(400, `Choose the receiving facility for ${p.destination}.`);
      if (!isFacilityAuthorized(req.user, facility)) fail(403, facilityDeniedMessage(facility));
      const status = dispatching ? 'IN_TRANSIT' : 'ARRIVED_DESTINATION';
      const location = locationLabel(facility);
      const note = dispatching ? `Onward dispatch from ${location} to ${p.destination}.` : `Onward parcel received at ${location}.`;
      const result = await tx.parcel.update({ where: { id: p.id }, data: dispatching ? { onwardDispatchedAt: new Date() } : { status, locationId: facility.id } });
      if (!dispatching) await tx.parcelTransfer.create({ data: { parcelId: p.id, fromLocationId: container.destinationId, toLocationId: facility.id, actorId: req.user.id } });
      await tx.trackingEvent.create({ data: { parcelId: p.id, status, location, note, originalNote: note, actorId: req.user.id, facilityId: facility.id } });
      await containerAudit(tx, req.user, container.id, `ONWARD_${action}`, `${p.trackingId} · ${note}`);
      return result;
    });
    res.status(201).json(parcel);
  } catch (e) { next(e); }
});
export default router;
