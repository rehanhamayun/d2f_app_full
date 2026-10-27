# D2F Milestone 1 corrections — implementation and assessment

27 October 2026. This document responds to the 15 review messages received after the Milestone 1 walkthrough. It records what was changed in the local source, what was verified, and what still requires a D2F decision. It is not a production deployment report or client acceptance.

## Status at a glance

- Items 1–10 are implemented in the local Flutter app, Express/Prisma backend and Admin dashboard.
- Items 11–13 (multi-package, sea pricing and advanced container routing) were assessed only. No scope, code or budget was changed for them.
- Item 14 (D2F ownership of source, backend, database and hosting) is **not yet confirmed**. The current GitHub and Railway assets are not demonstrably D2F-owned; see “Ownership and account control”.
- Item 15 (scope/budget approval) remains with D2F. The work in items 1–10 is treated as Milestone 1 correction work already covered by the agreed scope.
- The hosted backend and published clients have **not** been updated from this workstation. The new migration and clients must be deployed together before these corrections are live.

## Response to the review messages

| # | Request | Status | Result |
| --- | --- | --- | --- |
| 1 | Resolve the dependency alerts/Dependabot PRs and rerun tests | Done locally | `body-parser` 2.4.0 and `deepmerge-ts` 8.0.2 are pinned through npm overrides. Prisma remains on 6.19.3. Backend and dashboard audits report zero vulnerabilities. |
| 2 | Admin password change, email-based reset, D2F-managed admin accounts | Done in code; account control still open | Signed-in password change, one-time email reset codes, and Admin invitations are implemented. Recovery delivery needs D2F’s Resend/domain configuration. Asset ownership is item 14. |
| 3 | Allow same-city road shipments and domestic Togo cities | Done | ROAD may use one city only when pickup and delivery addresses are both present and different. AIR/SEA still require different cities. Togo city suggestions and custom cities are supported. |
| 4 | Manual pricing is acceptable | Confirmed | No automatic freight-rating engine was added. Admin quotes/orders remain manual. Sea-specific pricing is assessed in item 12. |
| 5 | Separate shipment origin from the receiving warehouse | Done | The commercial `origin` is stored separately from the current physical facility (`locationId`). Intake records the assigned warehouse; facility transfers and status history keep the physical location distinct. |
| 6 | Enforce status transitions, warehouse permissions and physical confirmation on the backend | Done | The backend now enforces the full forward lifecycle, facility assignment, physical confirmation, arrival/destination rules and actor/time/location history. |
| 7 | Fix the barcode/QR scan server error and test `D2F000000000005` | Done | Scan input is normalized before lookup (spaces, separators, case, URLs, JSON wrappers, numeric-only codes and legacy IDs). `D2F000000000005` is covered by regression tests. |
| 8 | Fix Activity/Parcels counters and list mismatch; respect staff scope | Done | A single `/parcels/board` response returns rows and counters from one database snapshot. “All” is the sum of status counts; search and status filters use the same snapshot. Access remains organization-scoped. |
| 9 | Remove “In Transit” from Location; save operational notes only; allow audited correction | Done | Status updates use actual D2F facilities, not arbitrary status labels. Notes are capped at 1,000 characters. Admins may correct any event note; staff may correct their own; the event actor, time and location are preserved and the correction is audited. |
| 10 | Distinguish Ready for Pickup, Released and Delivered; capture proof | Done | The lifecycle is now `READY_FOR_PICKUP → RELEASED → DELIVERED`. Release captures receiver, handover ID/reference and time. Delivery captures recipient, time, proof type and reference, with ID number required for ID-confirmed delivery. |
| 11 | Multi-package shipments | Assessment only | Current data model is one parcel = one package/label/weight. Options and impact are below. No code or budget change. |
| 12 | Sea-freight pricing | Assessment only | Manual pricing remains in place. Rate-table or container-allocation options are below. No code or budget change. |
| 13 | Container lifecycle and routing | Assessment only | Current container is a single direct `LOADING → DEPARTED → ARRIVED` movement. Multi-leg/transshipment/partial-unload options are below. No code or budget change. |
| 14 | Confirm backend/database/hosting ownership | Open | Source, Railway, database, dashboard, email and signing assets are not yet verified as D2F-owned. Required transfer actions are listed below. |
| 15 | Do not change scope/budget without approval | Acknowledged | Items 11–13 are not started. A written D2F decision/change order is required before any implementation or budget adjustment. |

## What was implemented (items 1–10)

### 1. Dependency security

- Added npm `overrides` in `backend/package.json`:
  - `body-parser` → **2.4.0** (the fixed release proposed by Dependabot PR #1).
  - `deepmerge-ts` → **8.0.2** (the fixed transitive release).
- Kept `@prisma/client` and `prisma` on **6.19.3**. A Prisma 7 upgrade is a major-version migration and was not required to close the reported advisories; it should be scheduled and tested separately rather than mixed into a security patch.
- `npm audit` reports **0** vulnerabilities for both `backend` and `admin-dashboard`.
- The Dependabot PRs themselves could not be inspected from this session because GitHub CLI is not authenticated and the remote repository is not publicly readable. The lockfile was verified directly instead.

### 2. Admin password management

- `POST /auth/password/change` verifies the current password, hashes the new one with bcrypt, revokes other sessions, and returns a fresh session token so the current device stays signed in.
- Email reset uses a six-digit, single-use, ten-minute code with a five-attempt limit. A successful reset revokes existing sessions.
- The Flutter staff/customer account screen and the Admin dashboard header both expose the change-password flow.
- Admin invitations now support the `ADMIN` role. The invitation is bound to one email and one role, is issued only by an authenticated administrator, and the new account inherits the issuer’s organization.
- Email recovery requires `RESEND_API_KEY` and `AUTH_FROM_EMAIL`. Without them, the API returns a clear 503 message instead of pretending an email was sent.

### 3. Road rules and domestic Togo

- AIR and SEA reject same-city origin/destination pairs.
- ROAD permits a same-city route only when both a pickup address and a delivery address are present and differ after normalization.
- The Flutter shipment form and Admin shipment form use the same rule; the backend re-validates every create and edit.
- Domestic Togo suggestions: Lomé, Kara, Sokodé, Atakpamé, Kpalimé, Tsévié, Aného, Dapaong, Bassar and Notsé. Staff can still enter a custom city/country.
- `pickupAddress` is stored on the parcel and shown in the app and Admin detail views.

### 4. Manual pricing

- The current system records manual quotes/orders in Admin commerce; it does not calculate freight from weight, volume or container space.
- No automatic pricing was introduced. “Manual pricing acceptable” is treated as the current operating rule.
- Sea-specific rate structures are assessed separately in item 12.

### 5. Origin versus receiving warehouse

- `Parcel.origin` / `destination` are the commercial route.
- `Parcel.locationId` is the current physical facility. Staff intake records the staff member’s assigned warehouse; later physical events update the facility.
- Facility-to-facility movement is recorded through `ParcelTransfer` with from/to facility, actor, note and time.
- The app and Admin forms explain that origin is where the shipment starts, while the receiving warehouse is recorded at intake.

### 6. Status, location and permission enforcement

The backend lifecycle is now:

```text
REQUESTED → RECEIVED → PROCESSING → IN_TRANSIT
          → ARRIVED_LOME / ARRIVED_DESTINATION
          → READY_FOR_PICKUP → RELEASED → DELIVERED
```

- Every physical status requires a real D2F facility.
- All physical statuses except `PROCESSING` also require `confirmed: true`, meaning staff physically verified the parcel at that facility.
- Staff can confirm only at their assigned facility. Administrators can operate at any facility.
- `IN_TRANSIT` must be confirmed from the facility currently holding the parcel.
- `ARRIVED_LOME` must be a Lomé, Togo facility. `ARRIVED_DESTINATION` must match the parcel’s destination country/city.
- A parcel cannot be marked ready for pickup at a facility it has not physically reached; a transfer must be recorded first.
- Container loading advances a received parcel to `PROCESSING`, requires the parcel to be at the container origin, and records the facility. Container-managed parcels cannot bypass departure/arrival through the individual status endpoint.
- Every event keeps its actor, timestamp, location and note. Existing events are not deleted when a correction is made.

### 7. Barcode/QR scanning

- Added `lib/core/tracking_code.dart`; scan and manual lookup now send one canonical value.
- Handles:
  - `D2F000000000005`
  - lower case and scanner whitespace
  - grouped digits such as `D2F 0000 0000 0005`
  - hyphen/underscore separators
  - percent-encoded tracking URLs
  - JSON wrappers such as `{"trackingId":"D2F000000000005"}`
  - 12- or 15-digit numeric-only Code 128 labels
  - legacy `D2F-2026-000101` identities
- Regression tests cover `D2F000000000005` in all of the above forms.

### 8. Activity/Parcels counters

- Added `GET /parcels/board`. It returns the visible rows, filtered total and per-status counts from one database transaction.
- The Activity screen uses that single response. “All (n)” is the sum of the status counts; each chip count matches the rows returned under the same search/filter.
- The endpoint is organization-scoped; staff do not see another organization’s parcels.
- The previous injected loaders remain as a test/preview fallback, but production uses `/parcels/board`.
- Backend regression coverage asserts that the sum of counts equals the total and that a filtered page keeps the same count.

### 9. Location dropdown and notes

- “In Transit” and other status labels are no longer accepted as locations. The app loads the organization’s actual facilities and sends `locationId`.
- The backend resolves legacy labels only against real facilities and rejects unknown values.
- Notes are limited to 1,000 characters and stored on the tracking event.
- `PATCH /parcels/:id/events/:eventId/note` corrects a note without deleting the event. Admins may correct any event; staff may correct only events they recorded. The original actor, time and location remain, and an audit record stores the before/after note.

### 10. Ready for Pickup, Released and Delivered

- **Ready for Pickup** means the parcel is physically at the pickup facility.
- **Released** means the parcel has been handed over for collection/delivery. It requires:
  - receiver name
  - handover ID/reference
  - handover date/time
  - facility confirmation
- **Delivered** means the recipient has received the parcel. It requires:
  - recipient name
  - delivery date/time
  - proof type: signature, photo, ID confirmation or recipient confirmation
  - proof reference
  - recipient ID number when proof type is ID confirmation
  - facility confirmation
- The app and Admin dashboard enforce the same required fields; the backend rejects incomplete handovers.

## Assessment-only requests (items 11–13)

No code, migration or budget change has been made for these items. They need a written D2F decision before work starts.

### 11. Multi-package shipments

**Current model:** one parcel record has one package type, one weight, one label and one tracking number. A container manifest sums one weight per parcel.

**Requested behaviour:** multiple boxes/pieces handled under one shipment or tracking number.

**Options:**

| Option | What it provides | Operational trade-off | Indicative impact |
| --- | --- | --- | --- |
| A. Parent shipment with child pieces (recommended if every box needs its own label/scan) | One customer-facing shipment/tracking reference; each piece has its own label, weight, dimensions and scan history; manifests list pieces; the customer sees one grouped timeline. | Requires a new parent/child data model, label generation, scan/loading changes, counters, Admin and app screens, migration and tests. | Medium change order; several development days plus QA. |
| B. One parcel with piece count and total weight | Lightweight: one label and one tracking number; manifest shows “3 pieces, 24 kg”. | No per-piece label or scan; weaker control if pieces separate in transit. | Small change order. |

**Recommendation:** choose A if each physical box must be labelled and scanned independently. Choose B if D2F only needs to record that a shipment contains several pieces. The current single-package model remains unchanged until D2F chooses.

### 12. Sea-freight pricing

**Current model:** no automatic freight rating. Admin commerce quotes/orders are entered manually; parcel records do not carry a calculated freight price.

**Requested behaviour:** sea pricing, potentially based on volume/weight/container.

**Options:**

| Option | What it provides | Trade-off | Indicative impact |
| --- | --- | --- | --- |
| A. Manual shipment price | Staff enter a price/quote per shipment; no rate engine. | Fastest; matches “manual pricing acceptable”; relies on staff accuracy. | Small change order if a parcel-level price field/UI is required. |
| B. Admin-maintained rate table | Origin/destination/method rates per CBM or kg, minimum charge and currency; quote snapshots the rate used. | More consistent quoting; needs Admin maintenance and pricing rules. | Medium change order. |
| C. Container cost allocation | Enter a container cost and split it across parcels by CBM/weight. | Useful for shared sea containers; more complex accounting and rounding. | Medium-to-large change order. |

**Recommendation:** start with A or B. Do not add payment collection or invoicing as part of this correction; those remain separate scope. The current manual workflow is not blocked.

### 13. Container lifecycle and routing

**Current model:** a container has an origin facility, destination facility, method, seal and manifest. Lifecycle is `LOADING → DEPARTED → ARRIVED`. Departure updates all loaded parcels atomically; the manifest freezes at departure. A parcel can belong to at most one container.

**Requested behaviour:** richer lifecycle/routing, such as multiple ports/legs, transshipment or partial unloading.

**Options:**

| Option | What it provides | Trade-off | Indicative impact |
| --- | --- | --- | --- |
| A. Add container legs and intermediate events | Ordered legs with carrier, port/facility, ETD/ETA and arrival at each leg; partial unload at a leg; parcel transfer records. | Matches real transshipment operations; requires new models, UI, manifest versions and stronger concurrency rules. | Large change order. |
| B. Keep one direct container movement; use parcel transfers for facility moves | Current direct route plus audited facility-to-facility transfers. | No multi-port/transshipment support; simpler and already tested. | No change. |

**Recommendation:** keep B unless D2F confirms real multi-port or partial-unload operations. If A is required, define the exact route rules, who may unload where, and how the manifest should be versioned before estimating.

## Ownership and account control (item 14)

The ownership requirement is **not yet satisfied**. The following is the current evidence, not a claim of D2F ownership:

| Asset | Current state | Required action |
| --- | --- | --- |
| Source repository | Git remote is `github.com/rehanhamayun/d2f_application` (personal account). | Transfer/create the repository under a D2F-owned GitHub organization; add D2F as Owner/Admin; record the transfer. |
| Backend hosting | Railway project `production_house` is in the Managing Consultant’s Pro workspace. | Transfer the project to a D2F-owned Railway workspace/account, or recreate it under D2F ownership and migrate the database. |
| PostgreSQL | Railway PostgreSQL service in the same project; no public TCP proxy. | Confirm D2F owner access, backups and retention; transfer with the Railway project. |
| Admin dashboard | Cloudflare Pages project `d2f-admin-dashboard`. | Confirm the Cloudflare account is D2F-owned; transfer or recreate under D2F. |
| Email recovery | Resend is not configured (`RESEND_API_KEY` / `AUTH_FROM_EMAIL` absent). | Create a D2F-owned Resend account/domain and store the key in the hosting secret store. |
| Android signing | Release key and credentials are in the ignored `.local/` folder. | Place the keystore and recovery credentials in D2F-controlled custody; document the handover. |
| Google Play | Play Console ownership was not verified in this session. | Confirm D2F Owner/Admin access and the app listing. |
| Secrets | `.local/`, `backend/.env` and `android/key.properties` are ignored and untracked. | Rotate production secrets after the account transfer; never commit them. |

The repository also still needs D2F’s **written approval of the Flutter + Express/Prisma/PostgreSQL architecture**, because the original specification named FlutterFlow/Firebase. This was already an open Milestone 1 acceptance item and is not resolved by the corrections above.

## Scope and budget (item 15)

- Items 1–10 are corrections to the agreed Milestone 1 behaviour and are not treated as new scope.
- Items 11–13 are **not started** and are not included in the current budget. The options above are for decision only.
- No estimate above is a quotation. A change order should be agreed before any of items 11–13 is implemented.
- Deployment, physical-device scanning, printer compatibility and formal acceptance remain separate release steps.

## Verification performed

| Check | Result |
| --- | --- |
| Flutter test suite | **80 passed** |
| `flutter analyze` | No errors/warnings; 7 pre-existing enum-name style infos |
| Backend test suite | **47 passed** against an isolated PostgreSQL database with all migrations applied |
| Admin dashboard tests | **17 passed** |
| Admin production build | Passed (`vite build`) |
| Backend `npm audit` | 0 vulnerabilities |
| Admin `npm audit` | 0 vulnerabilities |
| Secrets tracked | None found in the current tree or in history for `.local/`, `android/key.properties`, `*.jks`, `*.keystore` or `backend/.env`; only placeholder example files are tracked |
| Scan normalization | `D2F000000000005`, spaced, URL, JSON, numeric-only and legacy forms covered |
| Migration | `backend/prisma/migrations/20261027032042_m1_operations_controls/` adds the handover/proof fields and `ParcelTransfer`; existing parcel identities and auth records are not rewritten |

The backend suite uses a temporary local PostgreSQL instance on loopback port 55439. The hosted Railway database was not modified.

## Release checklist

1. D2F approves the correction scope and records the architecture decision.
2. D2F confirms or completes the account/ownership transfers in item 14.
3. Configure `RESEND_API_KEY` and `AUTH_FROM_EMAIL` in the D2F-owned backend environment.
4. Deploy the new backend and apply `20261027032042_m1_operations_controls` before publishing the updated Flutter app and Admin dashboard.
5. Test one real parcel through `REQUESTED → RECEIVED → PROCESSING → IN_TRANSIT → ARRIVED_LOME → READY_FOR_PICKUP → RELEASED → DELIVERED`, including a printed label scan and proof capture.
6. Obtain D2F’s written acceptance; items 11–13 remain pending a separate decision.
