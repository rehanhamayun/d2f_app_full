# Customer shipment workflow — functional notes

Blueprint: the client's *D2F Shipping — Functional App Workflow & Operational
Design* reference (`design/screens/D2F_Shipping_App_Functional_Workflow_For_Rehan_REVISED.pdf`).
This page records what milestone 1 implements from it, the contracts shared by
the mobile app, the Admin dashboard and the backend, and the remaining alignment work.
The revised reference remains the target; this implementation record does not change milestone scope or certify acceptance.

## Booking model

- One customer request may declare many goods lines (`ParcelItem`, up to **20**
  physical-package rows, each with contents description/contents quantity, type,
  optional dimensions and optional weight) under a single
  shipment record — the "multiple physical packages" section of the reference.
- One row represents **one physical handling unit**. Quantity describes the
  contents inside it; six boxes must be six rows, so collection and labels
  cannot silently collapse six packages into one.
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
- Photos can link to a declared package through `itemId`; customer, staff and
  Admin views identify the associated package. Whole-shipment legacy photos
  remain supported.
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
| `POST /customer/parcels` | Create a request with goods lines; requires profile phone, recipient phone/address, truthful-contents/restrictions acknowledgment, and (pickup) collection address + future slot |
| `GET /customer/parcels` / `/:pid` | List / detail with items and image metadata |
| `POST /customer/parcels/:pid/images` | Attach a photo (raw bytes, metadata via query, optional `itemId` links one package) |
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
  `dropoff-details`), photos (`goods-photo-add-<row>`) and the create action
  (`customer-create-shipment`).
- Staff: `update_status_screen.dart` (mode-aware next statuses),
  `parcel_detail_screen.dart` (goods, photos, handover cards),
  `activity_screen.dart` (new status chips).
- Admin: `ShipmentModal` in `admin-dashboard/src/App.jsx` — handover mode,
  scheduled slot, goods list, photo grid and pickup-window input.

## Reference alignment

| Reference section | Status |
| --- | --- |
| §1 Account + request | Phone/email and recipient address enforced; explicit truthful-contents/restrictions checkbox and server timestamp implemented. Customer account contact address is still missing. |
| §2 Multiple packages per booking | Up to 20 physical-package rows with type, contents quantity, dimensions, photos and custody labels implemented. Independent package statuses/history and separate package destinations/recipients remain. |
| §3 Pickup / drop-off with slot confirmation | Scheduled pickup, reschedule/slot-clear events, reasons and partial-collection checklist implemented. Failed/cancelled pickup records, staff assignment, pickup fees and selectable drop-off facilities remain. |
| §4 Staff operations queue | Implemented (queue shows contact, method, goods, photos, addresses, collection choice) |
| §5 Separate status flows | Still a single forward shipment chain. Separate booking, pickup, warehouse, transport and handover dimensions remain required. |
| §6 Quotation / invoice / pickup fee | Not yet implemented. SEA still requires an overall weight; mode-dependent optional weight and consolidated pricing/payment snapshots remain required. |
| §7–11 Containers, manifests, Lomé receipt | Existing shipment-level containers remain. Planning versus loading, package-level scans, independent port arrival/physical receipt, maritime fields and reconciliation still require redesign. |
| §12 Labels, roles, audit | Existing role/audit controls retained; 4×6 package labels encode distinct package IDs and show sequence/type. Independent per-package handover and customer notifications remain. |

## Testing map

- `backend/test/customer_shipment_requests.test.js` — full request lifecycle,
  validation rules, image freezing and mode guards (51 backend tests green).
- `test/customer_shipment_screen_test.dart` — acknowledgment, package dimensions,
  photo-to-package binding across blank drafts, preview refresh, goods and handover
  enforcement incl. scheduling; `test/widget_test.dart` — status contract +
  delivery-mode + goods-image fixtures; `test/update_status_screen_test.dart`
  — mode-aware staff transitions; `test/reference_redesign_test.dart` —
  rebuilt customer flow navigation.
- `admin-dashboard/src/shipment-edit.test.jsx` and friends — admin modal/edit
  behavior (18 admin tests green).

## Continuation checkpoint — 28 October 2026

OpenCode's unfinished package-alignment block has been continued locally. Its
migration `20261028023513_item_packages_collect_photos` adds declaration
acknowledgment, package dimensions/type/codes, photo links and collection evidence.
The local development database already has this migration. Apply pending migrations
and regenerate Prisma before deploying the updated backend; then publish updated
clients together because customer creation now requires explicit acknowledgment.

- Pickup collection records every declared row as collected or missing with a
  required reason (maximum 300 characters). Zero collected packages cannot become
  `PICKED_UP`. No custody code or printable package label is issued to a missing row,
  including when the parent shipment later reaches `RECEIVED`.
- Custody codes follow declared positions (`<shipment>-P01`, `-P03` when P02 is
  missing) and stay stable. Label PDF contains a shipment cover plus one page per
  registered package. Both package barcode and QR encode that package code.
- Staff detail lookup accepts a saved package code within the signed-in organization;
  the detail view identifies the scanned row. Customer-safe tracking also accepts
  saved package codes and returns the existing limited **shipment** timeline. It
  does not yet provide independent package progress.
- Existing container loading still accepts shipment labels. Package labels are for
  package identification/detail lookup; package-level loading and receiving must be
  implemented before claiming compliance with reference §§9–11.
- Admin schedule edits now compare date values, so saving the same slot does not
  manufacture a reschedule event. Clearing a slot records an explicit event instead
  of crashing the transaction. Reschedule reasons are available in Admin edits.
- The package form fits compact screens, rejects non-finite dimensions, keeps the
  20-row limit, and maps photos correctly when blank draft rows are omitted.
  The customer detail refreshes after photo uploads; an upload failure preserves
  the request and reports the failed attachment rather than claiming creation failed.

Validation: **87 Flutter tests, 51 backend tests and 18 Admin tests pass**.
Flutter analysis has no errors or warnings (10 existing informational lint notices).
Checks include customer acknowledgment/dimensions/photo binding, backend
lifecycle/security regressions, collection checklists on both clients, Admin production build,
and rendered 4×6 PDF labels whose QR payloads were decoded for distinct packages.
Production deployment and physical printer/scanner acceptance have not been performed.
