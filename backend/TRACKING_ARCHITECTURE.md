# Permanent tracking identities

Every parcel keeps its UUID primary key, organization ID, public tracking number,
and assigned numeric sequence. New public numbers use the organization's unique
uppercase alphanumeric prefix (3–5 characters) plus a zero-padded 12-digit
sequence: `D2F000000000001`, `FAS000000000001`, `TAC000000000001`.
Previously issued 15-digit sequences and legacy `D2F-YYYY-NNNNNN` identifiers
remain accepted by the customer tracking UI and API. Existing parcel identities
are not renumbered.

`Organization.trackingCounter` stores the next sequence. A single `UPDATE ...
RETURNING` increments and allocates it inside the parcel creation transaction.
Concurrent writes for one organization serialize on its row; different
organizations allocate independently. The counter is never calculated from the
remaining parcels and cannot be decreased. Exhaustion fails explicitly; numbers
are not truncated or wrapped. Rolled-back creations have not issued a number;
clients receive an identity only after its transaction commits.

Two append-only database tables preserve identity reservations:

- `TrackingPrefixReservation` reserves each prefix and organization identity,
  even if the organization is later deleted. New prefixes are normalized to
  uppercase. A prefix cannot be changed, reassigned, or released by deactivation.
- `TrackingNumberReservation` retains each issued tracking number, parcel UUID,
  organization and sequence after a parcel is deleted. It contains no customer
  contact information. Unique constraints prevent issuing either identity again.

Database triggers reserve identities during record insertion and prevent updates
or deletion of reservation rows. Parcel UUIDs, tracking numbers, assigned
organizations, and sequences are immutable. Unique constraints additionally
protect the live parcel table and each organization's sequence. New parcel IDs
must be UUID-shaped; existing identifiers are preserved by migration.

Shipment creation retries use a unique `(organizationId, clientRequestId)` key
and an organization-scoped advisory lock. The same key can be used independently
by two partners; retries within one organization return its original parcel.
Customer requests additionally verify account ownership. Operational parcel,
customer, and Admin queries filter by the authenticated organization.

An unassigned account can resolve the single active organization during the
current D2F-only phase. With multiple active organizations, an ambiguous account
is rejected rather than assigned to an arbitrary partner. Future SaaS onboarding
must explicitly associate accounts and invitations with their organization and
reserve its prefix; the tracking data structure does not require replacement.

Migration backfills reservations for existing organizations and parcels and
advances counters beyond known numeric sequences. It does not delete shipments.
Archive operational records when possible. Do not reset counters or delete
reservation history during operational cleanup or database restoration.

The integration suite runs against an isolated local database and covers
concurrent allocation across organizations, normalized/duplicate prefixes,
immutable identities, deletion/recreation, counter protection, exhaustion,
rollbacks, independent request retries, and organization access isolation.
Synthetic reservation records intentionally remain in that test database after
fixture cleanup because reservations are permanent.
