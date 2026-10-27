import directoryRouter from './operations_directory.js';
import { Router } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { resolveOrganizationId } from '../tracking.js';
import { warehouseLock, fail, locationLabel, containerInclude, manifestFor, containerAudit } from '../warehouse.js';
import { SERVICE_COUNTRIES, COUNTRY_TIMEZONES, countryInLocation } from '../service_area.js';
import { isFacilityAuthorized, facilityDeniedMessage } from '../parcel_rules.js';
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
    if (status && !['ALL', 'LOADING', 'DEPARTED', 'ARRIVED'].includes(status)) fail(400, 'Choose a valid container status.');
    const where = { organizationId: req.organizationId, ...(status && status !== 'ALL' ? { status } : {}), ...(q ? { code: { contains: q, mode: 'insensitive' } } : {}) };
    const [containers, total] = await prisma.$transaction([
      prisma.container.findMany({ where, include: containerInclude, orderBy: [{ createdAt: 'desc' }, { id: 'asc' }], take: limit, skip: offset }), prisma.container.count({ where }),
    ]);
    res.json({ containers, total, limit, offset });
  } catch (e) { next(e); }
});
router.post('/containers', async (req, res, next) => {
  try {
    const { code, originId, destinationId, method = 'SEA', sealNumber, notes } = req.body || {};
    if (!text(code, 40) || !/^[A-Z0-9-]+$/i.test(code.trim()) || typeof originId !== 'string' || typeof destinationId !== 'string' || originId === destinationId || !['AIR', 'SEA', 'ROAD'].includes(method) || (sealNumber != null && !text(sealNumber, 80)) || (notes != null && !text(notes, 2000))) fail(400, 'Enter a container reference, two different locations and a shipping method.');
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const locations = await tx.location.findMany({ where: { id: { in: [originId, destinationId] }, organizationId: req.organizationId } });
      if (locations.length !== 2) fail(400, 'Choose locations belonging to your organization.');
      const origin = locations.find((location) => location.id === originId);
      if (!isFacilityAuthorized(req.user, origin)) fail(403, facilityDeniedMessage(origin));
      const container = await tx.container.create({ data: { organizationId: req.organizationId, code: code.trim().toUpperCase(), originId, destinationId, method, sealNumber: sealNumber?.trim() || null, notes: notes?.trim() || null }, include: containerInclude });
      await containerAudit(tx, req.user, container.id, 'CREATED', 'Container opened for loading');
      return container;
    });
    res.status(201).json(result);
  } catch (e) { if (e.code === 'P2002') return res.status(409).json({ error: 'This container reference already exists.' }); next(e); }
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
    if (!text(trackingId, 80)) fail(400, 'Scan or enter a tracking number.');
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const container = await tx.container.findFirst({ where: { id: req.params.id, organizationId: req.organizationId }, include: containerInclude });
      if (!container) fail(404, 'Container not found.');
      if (container.status !== 'LOADING') fail(409, 'Loading is closed for this container.');
      if (!isFacilityAuthorized(req.user, container.origin)) fail(403, facilityDeniedMessage(container.origin));
      const parcel = await tx.parcel.findFirst({ where: { trackingId: trackingId.trim().toUpperCase(), organizationId: req.organizationId } });
      if (!parcel) fail(404, 'Parcel not found.');
      if (parcel.containerId === container.id) return { parcel, alreadyLoaded: true };
      if (parcel.containerId) fail(409, 'This parcel is already assigned to another container.');
      if (!['RECEIVED', 'PROCESSING'].includes(parcel.status)) fail(409, 'Only received or processing parcels can be loaded.');
      if (parcel.locationId && parcel.locationId !== container.originId) fail(409, 'The parcel must be received at the container origin before it can be loaded.');
      const parcelOriginCountry = countryInLocation(parcel.origin);
      if (parcelOriginCountry && parcelOriginCountry !== container.origin.country) fail(409, 'Parcel origin does not match the container origin country.');
      if (parcel.method !== container.method) fail(409, 'Parcel and container shipping methods must match.');
      // Loading is the physical processing step, so a received parcel moves to
      // PROCESSING before the container can depart. This preserves the strict
      // RECEIVED → PROCESSING → IN_TRANSIT lifecycle.
      const nextStatus = parcel.status === 'RECEIVED' ? 'PROCESSING' : parcel.status;
      const updated = await tx.parcel.update({
        where: { id: parcel.id },
        data: { containerId: container.id, status: nextStatus, locationId: container.originId },
      });
      await tx.trackingEvent.create({ data: { parcelId: parcel.id, status: nextStatus, actorId: req.user.id, location: locationLabel(container.origin), note: `Loaded into container ${container.code}` } });
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
      await tx.parcel.update({ where: { id: parcel.id }, data: { containerId: null } });
      await tx.trackingEvent.create({ data: { parcelId: parcel.id, status: parcel.status, actorId: req.user.id, location: locationLabel(container.origin), note: `Removed from container ${container.code}` } });
      await containerAudit(tx, req.user, container.id, 'PARCEL_REMOVED', parcel.trackingId);
    });
    res.json({ ok: true });
  } catch (e) { next(e); }
});
router.post('/containers/:id/events', async (req, res, next) => {
  try {
    const { action } = req.body || {};
    if (!['DEPARTED', 'ARRIVED'].includes(action)) fail(400, 'Choose departure or arrival.');
    const result = await prisma.$transaction(async tx => {
      await warehouseLock(tx, req.organizationId);
      const container = await tx.container.findFirst({ where: { id: req.params.id, organizationId: req.organizationId }, include: { ...containerInclude, parcels: true } });
      if (!container) fail(404, 'Container not found.');
      if ((action === 'DEPARTED' && container.status !== 'LOADING') || (action === 'ARRIVED' && container.status !== 'DEPARTED')) fail(409, 'This container has already changed. Refresh before continuing.');
      const eventFacility = action === 'DEPARTED' ? container.origin : container.destination;
      if (!isFacilityAuthorized(req.user, eventFacility)) fail(403, facilityDeniedMessage(eventFacility));
      if (!container.parcels.length) fail(409, 'Load at least one parcel before departure.');
      const departing = action === 'DEPARTED';
      if (container.parcels.some(p => !(departing ? ['RECEIVED', 'PROCESSING'] : ['IN_TRANSIT']).includes(p.status))) fail(409, 'A parcel has an incompatible status. Review the container before continuing.');
      const location = locationLabel(departing ? container.origin : container.destination);
      const note = `${departing ? 'Departed' : 'Arrived at'} ${location} · Container ${container.code}`;
      const status = departing ? 'IN_TRANSIT' : (container.destination.country === 'Togo' ? 'ARRIVED_LOME' : 'ARRIVED_DESTINATION');
      const manifest = departing ? await manifestFor(tx, container) : undefined;
      if (manifest) manifest.provisional = false;
      await tx.parcel.updateMany({ where: { containerId: container.id, organizationId: req.organizationId }, data: { status, locationId: departing ? container.originId : container.destinationId } });
      await tx.trackingEvent.createMany({ data: container.parcels.map(p => ({ parcelId: p.id, status, location, note, actorId: req.user.id })) });
      await containerAudit(tx, req.user, container.id, action, note);
      return tx.container.update({ where: { id: container.id }, data: { status: action, ...(manifest ? { manifest } : {}) }, include: containerInclude });
    }, { timeout: 20000 });
    res.status(201).json(result);
  } catch (e) { next(e); }
});
export default router;
