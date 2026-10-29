import { fail, locationLabel } from './warehouse.js';
import { resolveOrganizationId } from './tracking.js';
import { destinationMatchesLocation, isFacilityAuthorized, validFutureDate } from './parcel_rules.js';
import { allocatePackageCodes } from './package_custody.js';
const noteText = value => typeof value === 'string' && value.trim() && value.length <= 1000;
export async function schedulePickup(tx, user, id, body = {}, legacy = false) {
  const organizationId = await resolveOrganizationId(tx, user);
  const parcel = await tx.parcel.findFirst({ where: { id, organizationId } });
  if (!parcel) fail(404, 'Parcel not found.');
  if (!['STAFF', 'ADMIN'].includes(user.role)) fail(403, 'Dispatch staff must confirm the pickup appointment.');
  if (parcel.serviceType === 'AIR_TRAVELLER' || parcel.deliveryMode !== 'PICKUP' || !(legacy ? parcel.status === 'PICKED_UP' && !parcel.pickupConfirmedAt : ['REQUESTED', 'PICKUP_SCHEDULED'].includes(parcel.status))) fail(409, 'Only an uncollected D2F pickup can be scheduled.');
  if (legacy && (user.role !== 'ADMIN' || !await tx.trackingEvent.findFirst({ where: { parcelId: id, status: 'PICKED_UP' } }))) fail(403, 'An administrator must review an existing recorded collection before assigning verification.');
  const when = legacy ? parcel.pickupScheduledAt || new Date() : validFutureDate(body.pickupScheduledAt);
  if (!when) fail(400, 'Confirm a pickup appointment at least one hour from now and within 90 days.');
  const facility = await tx.location.findFirst({ where: { id: typeof body.locationId === 'string' ? body.locationId : '', organizationId } });
  if (!facility || !destinationMatchesLocation(parcel.origin, facility)) fail(400, 'Select the intake warehouse for the shipment origin.');
  if (!isFacilityAuthorized(user, facility)) fail(403, 'Only dispatch staff assigned to this intake warehouse may schedule its pickups.');
  const driver = await tx.user.findFirst({ where: { id: typeof body.pickupDriverId === 'string' ? body.pickupDriverId : '', organizationId, role: 'DRIVER', isActive: true } });
  if (!driver) fail(400, 'Assign an active D2F driver to this pickup.');
  if (body.confirmed !== true) fail(400, 'Confirm the appointment and driver assignment with the customer.');
  if (legacy) {
    if (parcel.pickupDriverId === driver.id && parcel.pickupTargetLocationId === facility.id) fail(409, 'This verification is already assigned.');
    await tx.parcel.update({ where: { id }, data: { pickupDriverId: driver.id, pickupTargetLocationId: facility.id, locationId: null } });
    await tx.auditLog.create({ data: { actorId: user.id, action: 'LEGACY_PICKUP_DRIVER_ASSIGNED', entity: 'Parcel', entityId: id, detail: JSON.stringify({ driverId: driver.id, targetFacilityId: facility.id }) } });
    return { id, status: parcel.status, verificationAssigned: true };
  }
  if (parcel.pickupScheduledAt?.getTime() === when.getTime() && parcel.pickupDriverId === driver.id && parcel.pickupTargetLocationId === facility.id) fail(409, 'This pickup appointment is already confirmed.');
  await tx.parcel.update({ where: { id }, data: { status: 'PICKUP_SCHEDULED', pickupScheduledAt: when, pickupDriverId: driver.id, pickupTargetLocationId: facility.id, locationId: null } });
  const note = parcel.status === 'PICKUP_SCHEDULED' ? `Pickup rescheduled to ${when.toISOString()}; assigned driver ${driver.fullName}. ${noteText(body.note) ? body.note.trim() : 'Dispatch confirmed the updated appointment.'}` : `D2F confirmed pickup for ${when.toISOString()}; assigned driver ${driver.fullName}. Awaiting physical collection.`;
  await tx.auditLog.create({ data: { actorId: user.id, action: 'PICKUP_SCHEDULED', entity: 'Parcel', entityId: id, detail: JSON.stringify({ previousAppointment: parcel.pickupScheduledAt, when, driverId: driver.id, targetFacilityId: facility.id }) } });
  return tx.trackingEvent.create({ data: { parcelId: id, status: 'PICKUP_SCHEDULED', actorId: user.id, note } });
}
export async function confirmIntake(tx, user, parcel, body = {}) {
  if (parcel.serviceType === 'AIR_TRAVELLER') fail(409, 'Use D2F Connect for traveller intake.');
  if (!['STAFF', 'ADMIN'].includes(user.role)) fail(403, 'Warehouse staff must verify receipt.');
  const legacyVerification = ['RECEIVED', 'PROCESSING'].includes(parcel.status) && !parcel.warehouseReceivedAt;
  if (parcel.warehouseReceivedAt || (!legacyVerification && !((parcel.deliveryMode === 'PICKUP' && parcel.status === 'PICKED_UP') || (parcel.deliveryMode === 'DROP_OFF' && parcel.status === 'REQUESTED')))) fail(409, 'Warehouse receipt is not available at this stage.');
  if (!legacyVerification && parcel.deliveryMode === 'PICKUP' && (!parcel.pickupConfirmedAt || !parcel.pickupConfirmedById)) fail(409, 'The assigned driver must physically confirm collection before warehouse receipt.');
  const facility = await tx.location.findFirst({ where: { id: typeof body.locationId === 'string' ? body.locationId : '', organizationId: parcel.organizationId } });
  if (!facility || !isFacilityAuthorized(user, facility)) fail(403, 'Only authorized staff at the receiving facility can confirm warehouse receipt.');
  if (parcel.pickupTargetLocationId ? parcel.pickupTargetLocationId !== facility.id : !destinationMatchesLocation(parcel.origin, facility)) fail(409, 'This is not the approved receiving warehouse for this shipment.');
  if (legacyVerification && parcel.locationId && parcel.locationId !== facility.id) fail(409, 'Verify this legacy parcel at its recorded warehouse.');
  if (user.id === parcel.pickupConfirmedById) fail(403, 'Driver collection and warehouse receipt require separate people.');
  if (body.confirmed !== true || !noteText(body.note)) fail(400, 'Confirm physical receipt and record the warehouse inspection.');
  const items = await tx.parcelItem.findMany({ where: { parcelId: parcel.id }, orderBy: { position: 'asc' } });
  const scanned = typeof body.scannedTrackingId === 'string' ? body.scannedTrackingId.trim().toUpperCase() : '';
  if (scanned !== parcel.trackingId && !items.some(i => i.packageCode === scanned)) fail(400, 'Scan or enter the parcel or package tracking number at the warehouse.');
  const expected = items.filter(i => !i.notCollectedReason);
  const verified = body.verifiedItemIds;
  if (expected.length && (!Array.isArray(verified) || verified.length !== expected.length || new Set(verified).size !== verified.length || expected.some(i => !verified.includes(i.id)))) fail(400, 'Verify every collected package against the intake checklist before confirming receipt.');
  const now = new Date();
  if (parcel.pickupConfirmedAt && now < parcel.pickupConfirmedAt) fail(409, 'Warehouse receipt cannot precede physical collection.');
  await tx.parcelItem.updateMany({ where: { id: { in: expected.map(i => i.id) } }, data: { warehouseReceivedAt: now } });
  await allocatePackageCodes(tx, parcel);
  const status = legacyVerification ? parcel.status : 'RECEIVED';
  await tx.parcel.update({ where: { id: parcel.id }, data: { status, locationId: facility.id, warehouseReceivedAt: now, warehouseReceivedById: user.id } });
  await tx.auditLog.create({ data: { actorId: user.id, action: 'WAREHOUSE_RECEIPT_VERIFIED', entity: 'Parcel', entityId: parcel.id, detail: JSON.stringify({ facilityId: facility.id, verifiedItemIds: expected.map(i => i.id), legacyVerification, note: body.note.trim() }) } });
  return tx.trackingEvent.create({ data: { parcelId: parcel.id, status, actorId: user.id, location: locationLabel(facility), note: `${legacyVerification ? 'Existing warehouse custody verified' : 'Received and verified at warehouse'}: ${body.note.trim()}` } });
}
