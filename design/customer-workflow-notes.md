# Customer shipment workflow — functional notes

Blueprint: the client's *D2F Shipping — Functional App Workflow & Operational
Design* reference (`design/screens/D2F_Shipping_App_Functional_Workflow_For_Rehan_REVISED.pdf`).
This page records what milestone 1 implements from it, the contracts shared by
the mobile app, the Admin dashboard and the backend, and the next alignment
block agreed with the client.

## Booking model

- One customer request may declare many goods lines (`ParcelItem`, up to **20**
  lines, each with name/quantity/details/optional weight) under a single
  shipment record — the "multiple physical packages" section of the reference.
- Requests are submitted **before** physical receipt or pricing: they start at
  `REQUESTED` and staff move them forward through warehouse intake.
- The customer records the origin, destination, shipping method, recipient
  name/phone and destination address. Addresses are typed; a **Verify on
  Google Maps** button opens the composed address in Maps (optional
  convenience, no API keys).
- Registration already enforces full name, email and an international phone
  number; every request requires the sender's phone on the profile and a
  recipient phone.

## Collection: pickup or warehouse drop-off

- The customer selects the handover module on the request form:
  - **Pickup** — D2F collects the goods. Requires a collection address and a
    scheduled slot (`pickupScheduledAt` at least 60 minutes ahead, up to 90
    days). Optional instructions ride in the shipment notes.
  - **Warehouse drop-off** — the customer brings the goods; only the receiving
    facility details are recorded later.
- Staff confirm or adjust the slot when scheduling (`PICKUP_SCHEDULED` accepts
  an optional `pickupScheduledAt` in the admin/staff update form), record the
  actual collection at `PICKED_UP`, and record physical intake at `RECEIVED`.
- Mode awareness is enforced everywhere: drop-off shipments can never enter
  the pickup stages.

### Status contract

`REQUESTED → (PICKUP_SCHEDULED → PICKED_UP) → RECEIVED → PROCESSING →
IN_TRANSIT → ARRIVED_LOME | ARRIVED_DESTINATION → READY_FOR_PICKUP → RELEASED →
DELIVERED`

- Server truth: `PARCEL_TRANSITIONS` + `PICKUP_ONLY_STATUSES` in
  `backend/src/parcel_rules.js`.
- Flutter mirror: `kParcelStatuses` / `kAllowedTransitions` /
  `kPickupOnlyStatuses` / `allowedStatusesFor` in `lib/models/models.dart`.
- Admin mirror: `TRANSITIONS` / `PICKUP_ONLY_STATUSES` in
  `admin-dashboard/src/App.jsx`.
- Parity is asserted by tests on all three sides; the pickup stages are
  filtered out for drop-off shipments and no facility/physical-confirmation
  is required for them.

## Goods photos (optional)

- Up to **8** raw images per shipment (jpeg/png/webp, ≤ 4 MB each), uploaded by
  the customer with the request; attachments freeze once a shipment leaves
  `EDITABLE_REQUEST_STATUSES` (`REQUESTED`, `PICKUP_SCHEDULED`, `PICKED_UP`).
- Owner-only deletes before intake; serving endpoints stream the bytes:
  `/customer/parcels/:pid/images/:iid/raw` for the customer,
  `/parcels/:idOrTracking/images/:iid/raw` for staff/admin (the Admin
  dashboard fetches these with its `Authorization` header and revokes the
  object URLs when the modal closes).
- iOS usage strings for camera/photo library live in `ios/Runner/Info.plist`;
  Android needs no manifest entries for `image_picker`.

## API surface (customer)

| Method & path | Purpose |
| --- | --- |
| `POST /customer/parcels` | Create a request with goods lines; requires profile phone, recipient phone/address, and (pickup) collection address + future slot |
| `GET /customer/parcels` / `/:pid` | List / detail with items and image metadata |
| `POST /customer/parcels/:pid/images` | Attach a photo (raw bytes, metadata via query) |
| `DELETE /customer/parcels/:pid/images/:iid` | Remove a photo before intake |
| `GET /customer/parcels/:pid/images/:iid/raw` | Serve an attached photo |

Staff/admin keep the existing `/parcels` endpoints: PATCH accepts
`deliveryMode` and `pickupScheduledAt` in its whitelist, transition rules stay
server-side, and every customer request shows contact details, addresses,
goods and photos in the operational queues.

## Screens and keys

- `lib/screens/customer_shipment_screen.dart` — one form spanning goods
  (`customer-goods`, `customer-add-item`), recipient details (`customer-*`),
  handover (`handover-pickup` / `handover-dropoff`, `pickup-details` with
  `customer-pickup-address` / `customer-pickup-schedule`,
  `dropoff-details`), photos (`customer-photos`) and the create action
  (`customer-create-shipment`).
- Staff: `update_status_screen.dart` (mode-aware next statuses),
  `parcel_detail_screen.dart` (goods, photos, handover cards),
  `activity_screen.dart` (new status chips).
- Admin: `ShipmentModal` in `admin-dashboard/src/App.jsx` — handover mode,
  scheduled slot, goods list, photo grid and pickup-window input.

## Reference alignment

| Reference section | Status |
| --- | --- |
| §1 Account + request (phone, truthful declaration, restrictions acknowledgment) | Request data enforced; the explicit "acknowledge shipping restrictions" checkbox is planned with the flags/legal block |
| §2 Multiple packages per booking | Goods lines up to 20 implemented; per-package type, dimensions, package-level photos and package IDs/labels (**Box 1 of 6**) are the next work block |
| §3 Pickup / drop-off with slot confirmation | Implemented; pickup failure/reschedule reasons and partial-collection discrepancy (6 requested, 5 collected) are the next work block |
| §4 Staff operations queue | Implemented (queue shows contact, method, goods, photos, addresses, collection choice) |
| §5 Separate status flows | Single forward parcel chain with pickup stages; separate booking/pickup/warehouse dimensions remain the pricing/operations milestone |
| §6 Quotation / invoice / pickup fee | Not in scope for this block (pricing milestone) |
| §7–11 Containers, manifests, Lomé receipt | Pre-existing warehouse/container system unchanged |
| §12 Labels, roles, audit | Labels/QR already exist for parcels; customer request events audit-logged |

## Testing map

- `backend/test/customer_shipment_requests.test.js` — full request lifecycle,
  validation rules, image freezing and mode guards (50 backend tests green).
- `test/customer_shipment_screen_test.dart` — form, goods, handover
  enforcement incl. scheduling; `test/widget_test.dart` — status contract +
  delivery-mode + goods-image fixtures; `test/update_status_screen_test.dart`
  — mode-aware staff transitions; `test/reference_redesign_test.dart` —
  rebuilt customer flow navigation.
- `admin-dashboard/src/shipment-edit.test.jsx` and friends — admin modal/edit
  behavior (17 admin tests green).
