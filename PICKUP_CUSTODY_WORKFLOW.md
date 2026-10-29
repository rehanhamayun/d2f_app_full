# Pickup, warehouse receipt and container tracking

Customer pickup requests remain `REQUESTED` (shown as Pickup Requested) until
dispatch confirms an appointment, an active driver and an origin receiving
facility. Customer-preferred time (`pickupPreferredAt`) is separate from the
confirmed appointment (`pickupScheduledAt`). Dispatch may reschedule before
collection, with a recorded audit and tracking entry.

`REQUESTED → PICKUP_SCHEDULED → PICKED_UP → RECEIVED → PROCESSING → IN_TRANSIT`

Only the assigned driver can confirm actual collection through Driver Dispatch,
with a matching shipment/package scan, handover proof and any missing-package
reasons. This records driver custody and clears warehouse location. Drivers
cannot mark warehouse receipt. Active DRIVER accounts must belong to the same
organization; dispatch assigns them in the mobile app or portal.

Customer drop-off follows `REQUESTED → RECEIVED`, initially shown as Awaiting
Drop-off. Authorized warehouse staff confirm the actual receiving facility,
scan the shipment or a linked package, inspect and verify every expected package,
and record a condition note. Pickup receipt additionally requires the preceding
driver confirmation and a different receiving staff member. Wrong facilities,
missing package verification, invalid transitions and duplicate confirmations
are rejected on the backend.

At destination, authorized staff select collection or dispatch an assigned
delivery driver. Collection requires recipient proof; driver delivery is
confirmed only by that assigned driver. Existing `RELEASED` events remain valid
historical records; the new interface uses direct proof-backed delivery.

## Container association

One shipment is associated with one container. All non-missing packages must
have verified warehouse receipt at that container's exact origin. The route and
shipping method must match, and staff must explicitly confirm physical loading.
The original D2F tracking number stays unchanged; container departure and arrival
advance the associated shipment history. Splitting a shipment's packages across
multiple containers is not implemented by this release.

## Existing records

The migration preserves tracking IDs and existing event history. It does not
invent warehouse inspections or driver proof for historical stock. Legacy
received/processing stock needs physical warehouse verification before loading.
For a legacy picked-up parcel without recorded driver proof, an administrator
assigns driver verification and its receiving facility in the portal; the driver
then attests collection. This adds audit evidence without duplicating the old
pickup event. Previously saved customer appointment preferences are retained.

D2F Connect traveller transport remains a separate workflow; these driver tasks
exclude Air Traveller bookings.
