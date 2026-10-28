# D2F Connect · Air Traveller

D2F Connect is a managed small-parcel service. It has its own home card, customer
booking workspace, traveller registration, trips, assignment acceptance, payments
and manifests. Conventional Air Cargo remains in Shipping and uses an AWB carrier
reference attached to the permanent D2F tracking number.

## Services and records

| Service | Parcel serviceType | Operational record | Carrier reference |
| --- | --- | --- | --- |
| Air Cargo | AIR_CARGO | Conventional parcel / cargo operations | AWB, airline, flight, volumetric weight, customs references |
| Air Traveller / Connect | AIR_TRAVELLER | ConnectBooking → ConnectAssignment → ConnectTrip | Traveller trip and manifest; no AWB |
| Sea / Road | SEA / ROAD | Existing shipping operations | Existing workflow |

The legacy `method: AIR` transport field remains compatible with existing clients.
`serviceType` determines which service owns the workflow. Existing AIR records are
backfilled to AIR_CARGO. Connect records cannot enter cargo containers or use the
conventional status/edit/transfer endpoints. Staff scanning a Connect parcel in the
app opens its Connect booking. Public tracking exposes confirmed progress only.

## Customer parcel registration

Shipping now uses numbered route, goods, recipient and handover sections, followed
by a live request summary. Package descriptions, quantities, dimensions, optional
package photos, recipient contacts, pickup address and preferred time are retained.
The contents declaration is directly above the registration button. Submission
creates the actual persisted request and a unique tracking number; physical receipt
is confirmed separately by D2F. Both staff and admin can review the saved details.

## Connect customer journey

1. Choose the international departure city and destination, and an earliest travel
   date. The sender's own city can differ from the traveller's departure city.
2. Declare the category, item quantity, total actual weight, description, declared
   value, recipient information and destination delivery preference.
3. Choose Domestic Shipping, D2F drop-off or a pickup request. Domestic Shipping
   records the customer's private return address; pickup records a private
   collection address for D2F coordination. A pickup request is not a confirmed
   appointment.
4. Optionally request an eligible trip. The requested trip remains separate from
   the trip actually proposed and confirmed by D2F.
5. Submit the truthful-contents declaration. The booking receives its permanent
   D2F tracking number immediately. It is not automatically accepted or assigned.
6. Review and accept the complete quotation, with international and domestic fees
   shown separately. Read the verified D2F payment instructions in the booking.
   D2F records payment after verifying the funds.
7. For domestic shipping, use the carrier label provided by D2F after review,
   payment and confirmed assignment. Confirm actual domestic dispatch in the app.
8. Follow domestic and international confirmed events in the same booking.

## Traveller journey

A customer account can also register a traveller trip; this does not grant staff
permissions. The traveller submits route, departure time (explicitly entered in
local device time), flight, available baggage, accepted categories and an identity /
ticket verification reference. D2F completes verification before approving the trip.

Travellers review proposed permitted contents and accept or decline each parcel.
D2F must confirm an accepted assignment. At the approved receiving location, the
traveller inspects the contents and enters the single-use D2F collection code.
They can reject unsafe or noncompliant contents before collection. Their manifest
identifies each parcel by its own tracking number and actual weight.

## Domestic Shipping and privacy

For Dallas → New York → Lomé, the booking's international route is New York →
Lomé and the sender city is Dallas. The domestic stage covers the customer's parcel
moving to an approved New York receiving location; the international stage covers
receiving location → assigned traveller → destination D2F team → recipient.

- Each receiving facility or authorized partner has an explicitly approved public
  street address, city and country. Approval is configured in D2F Connect →
  Receiving locations, using facilities created in Locations.
- The assignment checks route direction, departure date, permitted category,
  traveller approval, verified actual weight and remaining reserved capacity.
- A trip without an approved receiving location near its departure city can be
  reviewed, but assignments remain blocked for admin review. The system never
  substitutes a traveller's personal address.
- Customers receive only public trip and receiving-location projections. Traveller
  email, phone, identity verification reference and personal profile are excluded.
- Traveller responses and manifests exclude customer and recipient identities,
  private addresses, contact details, domestic labels, payment details and prices.
- Customers can access only their own bookings. Trip and manifest access belongs
  to the trip owner or organization-authorized staff. Staff physical actions are
  restricted to their assigned facility; admin can coordinate across facilities.
- D2F issues collection codes only after approved contents, payment, confirmed
  assignment and physical receiving-location intake. Codes are hashed, expire
  after ten minutes, allow five incorrect attempts and are consumed once. Only
  the assigned signed-in traveller can use one. Revoked location approval blocks
  collection even if a previously issued code has not expired.

## Staff and admin runbook

The web portal has a dedicated D2F Connect navigation item, separate from cargo
shipments and containers. The app exposes Connect booking and trip operations to
staff and admin through its home card.

1. Admin approves receiving locations, verifies traveller identity/ticket/eligibility
   and accepted categories, and approves the trip. No fictional trips or business
   rates are automatically inserted into production.
2. Admin configures directional prices. Clothing can be per kg; phones and laptops
   per item; documents up to 500 g can be flat. Heavier documents and exceptional
   goods require a manual quote. Initial pricing currency is USD.
3. Staff/admin reviews contents and records verified actual weight. D2F proposes a
   compatible trip; traveller acceptance and final D2F confirmation are separate.
4. Admin sets any manual quotation and domestic carrier cost, provides verified
   payment instructions, then records the unique received-payment reference after
   the customer accepts the price.
5. Staff/admin enters a manual HTTPS domestic label, carrier and domestic tracking
   reference. The approved receiving team records physical arrival and condition.
6. The receiving team checks the parcel and traveller and issues the collection
   code. The traveller inspects the contents and confirms collection in their app.
7. Staff/admin confirms actual departure. Every active assignment must have been
   confirmed and physically collected. The manifest closes to reassignment.
8. The approved destination team records receipt, marks readiness, verifies the
   recipient and records the actual delivery with identity/proof reference.
   Only that completed handover marks the parcel Delivered.

Admin can record compensation and operating expenses for each trip. The portal
shows collected international revenue and estimated operating profit after those
costs. Domestic carrier charges are displayed separately as pass-through costs.
Exceptional corrections require an admin audit entry; they cannot rewrite or remove
confirmed custody/departure records through the regular assignment controls.

Capacity mutations are serialized per organization in database transactions.
Proposed, accepted and confirmed assignments reserve actual weight. Declines and
pre-collection removals free capacity; verified weight changes recheck it. Accepted
quotation snapshots survive later rate changes. Payment booking/reference uniqueness
and serialized writes prevent duplicate ledger entries and repeated confirmations.

## MVP boundaries

Domestic carrier acceptance, labels and tracking updates are managed manually by
D2F. No carrier-label purchase API is called. Payment instructions and confirmations
support D2F's existing manual payment channels; there is no new card processor,
automatic charge, refund or traveller payout integration. Identity/ticket/customs
eligibility is verified by D2F using the recorded reference and review notes.

Tracking history is available in-app on load/refresh. Push, SMS and email delivery
are not configured by this module. Pickup and final delivery requests require D2F
coordination; creating a request does not promise an appointment or courier.

## Release and verification

Apply `20261028160000_connect_air_traveller` with `prisma migrate deploy`, generate
the Prisma client, then deploy the backend before the portal and Android app.
The migration is additive and retains existing parcel UUIDs and D2F tracking IDs.
Configuration can then be completed in Connect → Receiving locations and Rates.

Local verification uses a separate PostgreSQL database. Tests cover the complete
domestic/traveller/delivery journey, privacy and role boundaries, direction/category
matching, concurrent capacity reservations, verified-weight changes, manual quotes,
accepted price freezing, payment retries, receiving-facility enforcement, revoked
location approval, OTP failures/reuse, departure locks and final handover evidence.
Flutter tests cover persisted booking fields, the declaration before submission,
compact screens, enlarged text and separate traveller registration. Portal tests
cover staff controls, quotation errors/fee precision and Air Cargo AWB separation.

Screenshots: `design/verification-connect/` and refreshed customer verification
screens under `design/verification-customer/`.
