# D2F SHIPPING LLC — COMPLETE PROJECT MEMORY & MASTER AI CONTEXT

**Purpose:** Permanent, copy-ready project context for another AI assistant, designer, developer, or project manager.  
**Knowledge cutoff:** 20 October 2026.  
**Document type:** Product + business + commercial + technical specification; **not** a development log.  
**Rule of interpretation:** This describes the intended project and requirements. It does not certify that any functionality is implemented, tested, accepted, paid for, or released. The executed agreement and later explicit written client decisions take precedence wherever they differ from this summary.

---

## 1. PROJECT IDENTITY

- **Client / business:** D2F Shipping LLC (also called “D2F Shipping” or “D2F”).
- **Business focus:** Logistics, freight forwarding, parcel delivery and shipment services, including shipping between the United States and West Africa.
- **Primary initial operating lane:** Omaha, Nebraska, United States → Lomé, Togo, especially ocean freight. Other AIR, SEA, and ROAD movements must be represented within the same shipping system. The architectural model accommodates legs, hubs, and partners in other locations when needed; do not imply that all potential routes are operational or included as special workflows.
- **Business address shown in contract:** 2658 N 90th Street, Omaha, NE 68134, United States. D2F should confirm the formal LLC/legal-notice address.
- **General business/contract email shown:** info@d2fshipping.com.
- **Developer / contracting individual:** Rehan Hamayun.
- **Developer contract email:** rehanhamayun65@gmail.com.
- **Developer contractual mailing address:** House 13, Street 17, Raja Akram Colony, Islamabad, Pakistan (as specified in the draft agreement).
- **Project:** A production-oriented, unified D2F Shipping logistics MVP: Android app, responsive customer web/PWA, admin/dispatcher web interface and shared secure backend.
- **Existing ecosystem:** FlutterFlow, Flutter/Dart custom code if necessary, Firebase and Google Cloud, with source and accounts under D2F ownership.
- **Known FlutterFlow project identifier referenced for implementation:** `d2-f-shipping-m1-qxgdh8`; treat this as a project locator to verify, not as a statement about completed functionality.
- **Overall fixed development price:** **USD $2,000**.
- **Four milestone payments:** **USD $500 each**, conditional on the specified working demonstration and written acceptance; **no upfront payment before the first working demo**.
- **Included beyond core shipping MVP:** Air Traveller and the official WhatsApp Cloud API integration; **plus exactly two basic monetization modules selected by D2F from four choices**.
- **Support:** 120 calendar days of no-fee correction for defects in the accepted MVP after final production handover.

## 2. WHAT THE CLIENT WANTS TO ACHIEVE

D2F wants a genuinely usable operations platform rather than only visually attractive screens or an isolated app prototype. The system must connect actual physical parcel handling, QR/barcode identification, freight/container processing, staff operations in Omaha and Lomé, shipment tracking, customer bookings, assigned driver/contractor work, invoices, manual payment tracking, Air Traveller baggage/cargo allocations and transactional WhatsApp notifications.

The product should:

1. Provide one consistent source of shipment and parcel truth across Android and web experiences.
2. Let authorized employees receive/register parcels quickly and accurately, identify them with unique IDs and scan/print labels.
3. Support an operational Omaha-to-Lomé sea-freight lifecycle, including manifests and delivery/release status.
4. Give customers self-service booking, pickup requests, tracking and invoice/balance visibility.
5. Give drivers/contractors a Togo Load Board and assigned job workflow, including pickup/delivery status and proof of delivery.
6. Support AIR/SEA/ROAD booking and Air Traveller capacity management.
7. Keep financial records of invoices, partial/full **manual** payments and outstanding amounts.
8. Trigger appropriate WhatsApp transactional notifications using the official Meta API.
9. Be controllable by D2F without permanent reliance on the developer’s private accounts.
10. Allow D2F to generate some early revenue using two tightly scoped commercial modules while maintaining the fixed project budget.
11. Use a data model that does not obstruct later SaaS, logistics-partner or D2F Trade expansion; those future products are **not** automatically part of the current MVP.

## 3. DELIVERY SURFACES AND USER ROLES

### 3.1 Delivery surfaces

- **Android application:** A single installable Android app with distinct secure interfaces for **Staff, Customer, and Driver/Contractor**. Admin permissions and operations may be exposed as appropriate, but a separate full Admin/Dispatcher web dashboard is included.
- **Customer web portal / PWA:** Responsive browser access to the agreed customer booking, tracking, pickup and billing functions, operating on the same backend data.
- **Admin/Dispatcher web application:** Role-protected administration of users, operational locations, bookings, parcels, containers, pickups, load-board jobs, drivers, invoices and payments.
- **Release artifacts:** A demonstrable Android **APK** and, at final release, signed production **AAB** suitable for D2F’s Google Play Console submission.

### 3.2 Roles and authority

**Admin / Dispatcher**
- Manage staff/users, customer records, drivers/contractors, access assignments and permitted roles.
- View and control shipping/warehouse operations in authorized locations.
- Oversee bookings, parcel history, manifests, containers, load-board assignments, Air Traveller allocations, invoicing and manual payment recording.
- Manage the two selected revenue modules and their records.
- View appropriate audit and operational information.

**Warehouse Staff / Agent**
- Sign in securely and access only authorized operations.
- Register and look up parcels, scan QR/barcodes and update allowed warehouse events.
- Generate/reprint 4×6 labels, load parcels into containers and operate permitted departure/arrival/release stages.
- View customers and operational records necessary for their assigned responsibilities.

**Customer**
- Register/log in, request shipments and choose AIR, SEA or ROAD.
- Request or schedule pickup, view booking history, own parcel tracking and permitted invoices, payments and outstanding balances.
- Use the Android Customer experience or the customer PWA.
- Access only records associated with their own customer account.

**Driver / Contractor**
- Sign in with a permission-limited account.
- Browse approved Togo Load Board opportunities and/or receive direct assignment.
- Accept or proceed with permitted work, update collection/delivery statuses and attach proof-of-delivery photo.
- View completed-job history and manually recorded payout status.
- Access only authorized/assigned tasks and permitted data.

**Air Traveller**
- An Air Traveller record represents a person/flight and baggage/cargo capacity. It has a dedicated operational workflow. A separately self-registered Traveller app role or marketplace is **not implied** by the fixed MVP; confirm with D2F before adding one.

**Authorization requirement:** Roles must be enforced by backend rules/functions and record ownership, not solely by hiding navigation buttons or screens.

## 4. COMPLETE FUNCTIONAL REQUIREMENTS

### 4.1 Authentication and accounts

- Secure sign-in and appropriate account registration/creation flows.
- Distinct Staff, Customer and Driver/Contractor roles; controlled Admin privileges.
- Session handling, logout, account-disabled/error states and appropriate password recovery.
- Location- and organization-aware privileges where operationally applicable.
- Staff or customers must not be able to elevate their own roles or inspect other customers’ private records.

### 4.2 Parcel registration / receiving

- Authorized staff can select an existing customer or create/associate a customer through permitted workflow.
- Collect customer/shipper and recipient information, package type, weight, and notes. Suitable additional fields include origin/destination and contact/contents information where approved.
- Support real physical items such as boxes, barrels, TVs, appliances, furniture, pallets, vehicles and oversized freight where appropriate.
- Generate a permanent **internal parcel UUID** and a separate, human-readable, public **D2F tracking ID**.
- Generate a QR code/barcode tied to the actual saved parcel and provide camera scanning plus a manual tracking-number lookup fallback.
- Preserve the parcel’s identity and history across subsequent bookings, shipments, legs, containers and delivery stages.
- Avoid duplicate registrations or unintended double-updates if users retry actions.
- Allow staff to search and retrieve parcels by tracking/reference information.
- Show current operational status and a timestamped, traceable history of significant events.

### 4.3 4×6 parcel labels

- Create printer-ready **4-inch × 6-inch labels** with correct tracking identity and machine-readable QR/barcode.
- Display readable D2F/customer/recipient/route information only as approved and necessary.
- Allow label preview, printing and reprinting without changing the parcel’s identity.
- Scanning a printed code must retrieve the corresponding parcel.
- The exact label layout, printer model and printing interface need D2F confirmation for hardware-specific compatibility; standard print/PDF workflows do not automatically imply direct ZPL/Bluetooth support for all printers.

### 4.4 Warehouse and sea-freight/container operations

- Manage warehouse handling in Omaha and receiving/arrival operations in Lomé.
- Create containers and assign parcels by scanning; display contained items and appropriate totals.
- Generate basic printable/downloadable **container manifests**.
- Support loading/manifest review, Omaha departure, Lomé arrival, Ready for Pickup, Released and Delivered stages.
- Restrict conflicting container assignments and unauthorized after-dispatch edits; record material corrections.
- Maintain links among parcels, containers, shipping legs and customer-visible history.
- Make route events and statuses actually persist to the backend and appear accurately in appropriate screens.

**Primary ocean lifecycle:**

`Parcel registered → label/QR issued → parcel assigned to container → manifest prepared → departed Omaha → arrived Lomé → ready for pickup → released / delivered (as applicable)`

“Released” and “Delivered” are distinct operational concepts; precise transitions/role permissions should follow D2F’s approved procedures rather than assumptions.

### 4.5 Shipments, legs and tracking

- Represent **AIR / SEA / ROAD** booking and transport modes, including multiple legs where appropriate.
- Track the same parcel through its complete journey using a stable internal identifier and public tracking number.
- Record status events with timestamp, actor and location/context where applicable.
- Expose an operational detail view for staff/admin and a customer-safe tracking timeline for the relevant customer.
- Avoid contradictory screens, duplicate scans or updates that appear successful locally but were rejected by the backend.
- Multi-leg shipment and location modeling should allow later partner routes without assuming new countries or business modules are already in scope.

### 4.6 Customer Android experience and responsive PWA

- Customer sign-up/login and profile.
- **Booking requests** with AIR, SEA or ROAD selection.
- View own booking history and relevant shipment/parcel details.
- Track parcels and see current shipping/delivery checkpoints.
- Request/schedule pickup and view pickup/delivery status.
- View invoices, payment status, transaction history when displayed, and **outstanding balance**.
- Access clear contact/help information and error/empty/loading states.
- Ensure Android and web views use the same data and permission rules.

### 4.7 Driver / Contractor and Togo Load Board

- Driver/contractor login and profile.
- **Togo Load Board** containing available/eligible jobs.
- Dispatcher direct assignment and a suitable job acceptance workflow.
- Job details and status updates for pickup, movement and delivery.
- **Proof of delivery via photo upload** for agreed delivery actions.
- Completed jobs/history and a **manual payout-status record** for the driver.
- The MVP does not promise automated route optimization, real-time GPS fleet tracking, driver payroll or payout processing.
- Client should specify posting eligibility, whether acceptance is automatic or requires approval, cancellations, and any operational job rules not captured in the agreement.

### 4.8 Invoices and payments

- Generate invoices with customer and shipment/parcel references and detailed line items.
- Compute totals and outstanding balances consistently.
- Record manually received payments, including **full or partial amounts**, date, method/reference where needed and authorized operator.
- Maintain an auditable payment history and status labels: **UNPAID / PARTIALLY PAID / PAID**.
- Create downloadable/printable **PDF invoices and payment receipts**.
- Show applicable invoices, history and remaining balance to the corresponding customer.
- The fixed MVP **does not include** online card/ACH/Mobile Money gateways, automated payment capture, payment webhooks, refunds or advanced rate/pricing engines.

### 4.9 Air Traveller (included within total fixed price)

A lean workflow for assigning D2F parcels to a traveller’s available baggage/cargo capacity. It is **not** a full airline cargo-management product or open traveler marketplace.

- Create/manage Traveller: name, contact, airline, flight number, origin, destination and departure/arrival dates.
- Enter total baggage/cargo allowance or available space in kilograms.
- Assign existing D2F parcels/bookings with weight and tracking reference.
- **Automatically reduce remaining available kg** when parcels are allocated and restore capacity when valid allocations are removed.
- Prevent allocation beyond available capacity.
- Generate a printable/downloadable Traveller manifest with parcel tracking IDs and assigned weights.
- Statuses: **PLANNED / OPEN / FULL / DEPARTED / ARRIVED / CLOSED**.
- Air parcel movement must use the shared D2F tracking system; customer sees appropriate AIR information in Android/PWA.
- The $2,000 total comprises an **$1,800 base MVP plus $200 Air Traveller allocation**; the Air Traveller amount is **already included**, not an extra surcharge.
- Confirm any additional traveller identity, baggage acceptance, forbidden-item, custody, airline or cross-border business rules with D2F before assuming them.

### 4.10 WhatsApp Business notifications

- Integrate the **official Meta WhatsApp Cloud API** in the agreed shipping MVP **without an extra developer integration fee**.
- Intended notification events: booking confirmation, pickup scheduling, parcel receipt, Omaha departure/shipment movement, Lomé arrival, Ready for Pickup, delivered status, and invoice/balance reminders.
- Use server-side authorized events, properly secured tokens, appropriate consent/opt-in and approved Meta templates.
- Log attempted and completed messages/errors as needed, and avoid accidental duplicate notifications on retries.
- **D2F pays any applicable Meta messaging/usage fees.** Business verification and message-template approval are under Meta’s control.
- If Meta approvals are pending when the rest of the product is handed over, the contracted production configuration/activation follows after approval without a new integration charge.
- An AI chatbot, full shared WhatsApp inbox, generalized campaign automation or CRM is **not** part of this MVP.

### 4.11 Admin/Dispatcher web dashboard

- Manage authorized users/roles and D2F locations.
- Manage customers and account associations.
- Review bookings, parcel intake, tracking, manifests, containers and pickup requests.
- Operate Omaha departure and Lomé arrival workflows.
- Create/assign/monitor Togo Load Board jobs and driver/contractor records.
- Manage Air Traveller listings/capacity/allocations/manifests.
- Generate/record/view invoices, manual payments, customer balances and receipts.
- Administer the **two selected** basic revenue modules.
- Provide usable search, filtering, error states, secure access and traceable material actions.

## 5. TWO INCLUDED MONETIZATION MODULES — CLIENT CHOOSES FROM FOUR

**Commercial commitment:** All four choices must be presented to D2F, but only **two basic modules** are included in the **same USD $2,000 fixed total**. D2F chooses which two. No additional development charge for the selected pair. The unselected options and advanced versions are separate future scope.

### Option A — Basic Marketplace / Managed Product and Service Catalogue

- Admin-managed product/service listings with image, category, description, displayed price and enquiry/contact action.
- Possible income: paid listings, referral/sales commissions arranged offline.
- Basic limit: no third-party seller dashboard, shopping cart, platform checkout, inventory syncing, integrated payouts or dispute handling.

### Option B — Basic Membership / Subscription Directory

- Up to three manually managed plans for customer, seller and business audiences.
- Display fees/benefits, accept membership requests and allow Admin to record manual payment plus membership start/end dates/status.
- Possible income: manually collected membership fees.
- Basic limit: **no automated recurring billing**, automated discounts, subscription payment gateway or independent SaaS tenants.

### Option C — Advertising / Sponsored Business Placements

- Admin creates clearly marked **Sponsored** promotional cards with image, business name, short description, contact link and start/end dates.
- Display sponsored placements in predefined app areas; cease displaying them after expiry.
- Possible income: D2F charges an agreed fixed placement fee, entered through existing invoicing/manual-payment workflow.
- Basic limit: no ad network, auctions, targeting system or advanced advertising analytics console.

### Option D — Buy For Me Service

- Customer submits a desired product URL, quantity and notes.
- Admin reviews and provides a quote showing item cost, D2F purchasing/service fee and applicable shipping charge.
- Customer accepts the quote; authorized staff records **manual payment**.
- Purchased goods are linked to an ordinary D2F parcel/shipping/tracking record.
- Possible income: purchasing-assistance service fee plus freight/shipping fee.
- Basic limit: **no automated retailer checkout**, retailer APIs, purchasing bots, procurement marketplace or automated payouts.

### Recommended pair — not an automatic selection

**Recommended: Option D (Buy For Me) + Option C (Sponsored Placements).**

- Buy For Me directly leverages shipping, invoicing and parcel tracking and creates a service-fee opportunity.
- Sponsored listings may produce simpler business-to-business advertising revenue without recurring-billing infrastructure.
- Actual profitability or revenue is not guaranteed.
- **D2F must expressly select its two options in writing.** Do not silently treat the recommendation as an approval.

### Integration into four milestones

- **M1:** Main working staff parcel APK and demo are unchanged; agree on the selected pair and minimal workflows.
- **M2:** Admin-access controls and administrative records for the selected pair alongside warehouse/admin work.
- **M3:** Customer-facing interactions, relevant quotes/listings and manual invoice/payment entries alongside customer/driver/finance work.
- **M4:** Complete integration tests, documentation, corrections and final handover for those two modules.

For the recommended pair, the key proof cases are: (D) request → quote → acceptance → manually recorded payment → trackable parcel, and (C) sponsored card created → displayed as sponsored with correct link/dates → not shown after expiry. Alternative selected pairs require equivalent agreed acceptance tests.

## 6. FOUR FIXED-PRICE MILESTONES — FULL SCOPE AND ACCEPTANCE

**Each milestone = USD $500. Total = USD $2,000. All milestone payments are acceptance-based, not advance deposits.** A real, installable working Android demo precedes the first payment. For every milestone: show deliverables and evidence, make the relevant source/current configuration accessible in D2F-owned accounts, commit source to D2F GitHub, allow D2F review and obtain **affirmative written acceptance** before payment becomes due.

### Milestone 1 — $500 — Working Android APK and Staff Parcel Foundation

**Deliverables**
1. Installable Android **test APK**.
2. Working Staff login and permission-aware navigation/access.
3. Parcel creation with customer/recipient details, package type, weight and notes.
4. Persistent internal UUID plus unique public D2F tracking ID.
5. Functional QR/barcode generation, actual parcel scanning/lookup and stored event/status history.
6. Working connected backend for these user journeys rather than placeholder screens.

**Acceptance demonstration**
1. D2F installs and opens APK on a real Android phone.
2. Authorized Staff logs in and creates a parcel.
3. New tracking ID and QR/barcode correspond to that record.
4. Staff scans/locates the record and makes an allowed status update.
5. Record and timestamped history remain after closing/reopening the app.
6. D2F gives explicit **written acceptance**.

**Payment trigger:** $500 only after demonstrated, accessible and accepted Milestone 1 deliverables. No money before the first working demo.

### Milestone 2 — $500 — Warehouse, Labels, Containers and Admin Operations

**Deliverables**
1. Accurate **4×6 label printing/reprinting**.
2. Parcel search and container creation.
3. Scan parcels into containers and produce basic printable manifests.
4. Omaha departure and Lomé arrival route event workflow.
5. Ready for Pickup, Released and Delivered handling.
6. Working Admin/Dispatcher web controls for authorized staff/users, customers, locations, bookings, parcels and containers.
7. Relevant event history, data consistency and permission checks.
8. Admin elements for the selected two revenue modules as agreed in their minimal scope.

**Acceptance demonstration**
1. D2F follows a test parcel from registration through container loading and manifest creation.
2. Shipment/parcel is marked departed Omaha then arrived Lomé using valid authorized actions.
3. Test parcel can be found by search; its label and container manifest can be printed.
4. Events remain chronological and correct.
5. D2F can operate applicable Admin controls and records.
6. D2F gives explicit **written acceptance**.

### Milestone 3 — $500 — Customer, Driver, Togo Load Board and Finance

**Deliverables**
1. Android Customer role and responsive Customer **PWA**.
2. Registration, AIR/SEA/ROAD booking requests and booking history.
3. Customer tracking, pickup request, pickup/delivery status and invoice/balance view.
4. Driver/Contractor role, Togo Load Board, eligible available jobs, direct assignment/acceptance, authorized job statuses, proof-of-delivery photo and completed-job history.
5. Manually recorded driver payout status.
6. Invoice creation/line items, full/partial manual payment records and balances.
7. PDF invoice and receipt.
8. Relevant customer-facing selected-monetization interactions and manual financial records.

**Acceptance demonstration**
1. Customer registers/logs in, makes booking, requests pickup, tracks parcel and sees own invoice and outstanding balance.
2. Driver is assigned/accepts authorized job, records pickup/delivery and uploads proof photo.
3. Admin records a **partial manual payment**; balance, statuses, history and downloadable PDFs are correct.
4. Role isolation is respected.
5. D2F gives explicit **written acceptance**.

### Milestone 4 — $500 — Air Traveller, WhatsApp, Final QA and Handover

**Deliverables**
1. Complete Air Traveller record, parcel assignment, capacity calculation, states and manifests.
2. WhatsApp Cloud API transactional event triggers/integration, subject to Meta account/template approvals.
3. End-to-end functional and security tests and remediation of agreed in-scope defects.
4. Final production-ready Android APK/AAB, production deployment and Google Play submission through D2F-owned account with required client approvals.
5. Complete source, FlutterFlow/Firebase/Google Cloud/GitHub access, rules/functions/configuration, technical and operational documentation, licenses and handover.
6. Final tests and documentation for the two selected monetization modules.

**Acceptance demonstration**
1. Authorized operator assigns weighed AIR parcels to Traveller; available kg changes accurately; over-capacity is blocked; manifest is printable.
2. Staff, customer, driver, container, admin, invoices, notifications and two revenue modules pass agreed end-to-end cases.
3. Security and integrity checks pass; no blocking agreed-scope defect remains.
4. Build/release artifacts and complete documentation are accessible in D2F-owned systems.
5. D2F signs **written final acceptance/handover**.

**Platform-dependent timing:** Developer prepares/submits the Android release through D2F Google Play. Google independently decides publication/review. Meta independently controls template/business approval; these are not guarantees of third-party acceptance on a fixed date.

## 7. ACCEPTANCE, PAYMENT, SCHEDULE AND SUPPORT TERMS

### Milestone review process

1. Developer submits working deliverables, demonstration/evidence, current relevant source and D2F GitHub commit.
2. D2F has an agreed **5–10 business-day** review window (up to 10) against written acceptance criteria.
3. D2F either expressly **accepts in writing** or identifies material reproducible failures against the agreed scope.
4. In-scope defects are fixed without an extra development fee, the work is resubmitted and retested.
5. **Silence, elapsed time, access, use or partial use is never deemed acceptance.** Only a positive written acceptance authorizes a milestone payment.

### Schedule

- Planning target: **10–16 calendar days of active development** after a ready kickoff and necessary project/accounts/sample-data access.
- This is a development target, not a promise that D2F review periods, bug retesting, Meta approval or Google Play review will finish in the same window.
- Actual acceptance tests and agreed functionality take priority over meeting an optimistic target date.

### Support period

- **120 calendar days** of no-fee correction of defects in the final accepted MVP, starting after final written production acceptance and handover.
- Initial-response targets for support incidents:
  - **Critical** (production unavailable, material data-loss or security issue): approximately **24 hours**.
  - **High** (important core workflow blocked or severely impaired): **2 business days**.
  - **Normal** (non-blocking agreed-feature defect): **3 business days**.
- These are **initial response/acknowledgment targets**, not guaranteed resolution deadlines.
- New modules, enhancements outside the agreed scope and third-party service outages are not included as free bug fixes.

## 8. REQUIRED TECHNICAL ARCHITECTURE AND DATA INTEGRITY

### 8.1 Stack and platform ownership

- Frontend: **FlutterFlow**, with custom Flutter/Dart implementation as needed for technical requirements, plus responsive web/PWA interface.
- Backend: **Firebase Authentication**, **Cloud Firestore**, **Firebase Storage** and **Firebase/Google Cloud Functions** (or approved secure Google Cloud services where appropriate).
- Source/version control: **D2F-owned GitHub** repository.
- External service: **Meta WhatsApp Cloud API**.
- Platform/deployment: Android APK/AAB and **D2F-owned Google Play Console**.
- D2F retains Owner/Admin control of FlutterFlow, Firebase/Google Cloud, GitHub, Play and other production services. Developer is a collaborator with appropriate limited access.
- Technical alternatives such as a custom REST backend can be proposed if necessary, but no switch to Base44, Node/Express or another architecture should be assumed without documented approval and preservation of all agreed functionality/ownership.
- Assess whether existing FlutterFlow/Firebase components can be reused/refactored; a **clean rebuild of the same contracted scope is covered at no extra fee if necessary**. This is a contractual delivery option, not an instruction to rebuild automatically.

### 8.2 Authoritative operational data model — conceptual

The useful logical entities include:

- `organizations`: D2F and permitted partner organizations, structured for secure future expansion.
- `locations`: warehouse, hub, pickup or delivery location with organization ownership and timezone.
- `users` / `roles`: identities, assigned organization and location access, role/permissions.
- `customers`: customer identity, contact and shipping/billing association.
- `bookings`: requests and AIR/SEA/ROAD service selection.
- `shipments`: logistics movement linked to one/more bookings and legs.
- `shipmentLegs`: individual AIR/SEA/ROAD segments, carrier, origin/destination and departure/arrival data.
- `parcels`: permanent UUID, public unique tracking number, people, weight, type, route, links and current status.
- `trackingIndex`: unique public tracking ID → parcel lookup, written/validated by trusted backend.
- `containers`, `bags`, `manifests`, `manifestItems`: physical handling units, scan membership and expected/actual contents.
- `events` / `auditLogs`: chronological parcel state transitions, operator actions and relevant administrative history.
- `actions` / `deviceState`: optional secure action/retry sequencing when an approved low-connectivity workflow requires it.
- `labelTemplates`: authorized 4×6 label layout/configuration.
- `documents`: manifests, invoices, receipts and proof-of-delivery files.
- `loadBoardJobs`, `driverAssignments`, `deliveryProofs`: Togo job workflow.
- `invoices`, `payments`, `customerBalances`: invoicing and manual payment ledger.
- `airTravellers`, `airTravellerAllocations`: flight/person/capacity and parcel allocations.
- `notificationJobs`: WhatsApp template event, recipient, status and audit data.
- Selected monetization entities such as `buyForMeRequests` / `quotes` / `sponsoredPlacements` / `membershipRecords` / `marketplaceListings` **only for the two chosen modules**.

These are conceptual entity names rather than a command to rename an existing database. Maintain consistent organization ownership, access boundaries and migration safety. A leg’s AIR/SEA/ROAD mode should be authoritative, with shipment-level mode summary derived from its legs when modeling multimodal freight.

### 8.3 Integrity and security principles

- Enforce organization, location, customer and driver-assignment boundaries on reads and writes through backend rules/functions.
- Never let mobile UI alone certify a parcel as scanned, a driver job as complete, or an invoice as paid. Relevant backend records must be updated and persist.
- Use trusted server actions/transactions for sensitive state changes, such as parcel registration identity, container loading, shipment status, invoice calculations, payment recording and privileged role assignments.
- Keep permanent IDs and an auditable event history rather than destructively replacing older parcel states.
- Reject duplicate financial transactions, invalid/over-capacity traveller allocations, contradictory parcel/container relationships and unauthorized status transitions.
- Secure WhatsApp tokens, service credentials and signing assets; never hardcode secret server tokens into the mobile client.
- Document and test necessary Cloud Firestore/Storage security rules, indexing and approved permissions.
- Handle weak connectivity transparently: show pending or failed actions; do not falsely report a persisted action. **Full advanced offline warehouse operation/synchronization is a future phase**, unless separately commissioned.
- Use real backend data instead of fictitious placeholders for acceptance testing.

## 9. UX, UI AND DESIGN REQUIREMENTS

The experience should look like a genuine, mature logistics product rather than a generic AI-generated mockup. Use consistent navigation, legible type, restrained but clear color hierarchy, sensible spacing, native-feeling Android interactions and high-quality responsive layouts. The app should look complete and operational, including realistic forms, populated states, empty/error states and clear permission-aware actions.

**Design considerations:**
- Fast warehouse use on Android phones: generous scan targets, large readable IDs, clear success/failure feedback and shortcuts for intake/scan/print.
- Role-appropriate distinct dashboard/navigation for Staff, Customer and Driver; Admin web functionality should be efficient for high-volume operations.
- Keep D2F branding consistent. Earlier presentation directions included **Graphite + Citron** and other design concepts; treat colors as a design direction to confirm against the client’s selected identity, not an immutable legal requirement.
- Customer-facing screens should emphasize tracking, bookings, current shipment milestones, pickup actions, invoices and balance.
- Driver-facing screens should emphasize available/assigned jobs, next actions, proof of delivery and history.
- Admin-facing screens should support search/filter, dashboards, manifests and financial record operations.
- Support appropriate desktop/tablet responsiveness for customer web/PWA and dispatcher controls.
- The final deliverable is functioning UI integrated with actual backend behavior, not just exported screenshots or mockups.

### Practical functional screen map

1. Splash/Auth Gate.
2. Login / Reset Password.
3. Admin/Dispatcher Dashboard.
4. Staff Dashboard.
5. Register New Parcel.
6. Scan Parcel / Manual Tracking Lookup.
7. Parcel Details and History.
8. 4×6 Label Preview / Print / Reprint.
9. Containers List / Create.
10. Container Detail and Manifest.
11. Shipment/Tracking Operations.
12. Customer Dashboard / My Parcels.
13. Customer Invoice Detail / Balance.
14. Driver Assigned Jobs.
15. Driver Job Detail / Proof of Delivery.
16. Togo Load Board.
17. Air Traveller Management.
18. Admin Invoice List / Editor.
19. Record Manual Payment.
20. User / Role Management.
21. Profile / Settings / Help.
22. Error / Connectivity / Pending Action UI.
23. Customer Booking / Pickup Request and History (can be separate routes or grouped with Customer Dashboard).
24. Revenue-module screens for **the two chosen** monetization options (admin and customer views as applicable).

This is a **functional inventory**, not a contractual promise of exactly 24 separately named UI pages. Equivalent well-designed screen structure is acceptable if all agreed functions remain discoverable, usable and secure.

## 10. D2F OWNERSHIP, SECURITY, IP AND TERMINATION SAFEGUARDS

- **Client-owned accounts from day one:** FlutterFlow, Firebase/Google Cloud, GitHub, Google Play and operational data are D2F-controlled; D2F maintains Owner/Admin privileges.
- **Before each payment:** the milestone source is committed into D2F GitHub and associated FlutterFlow pages, backend/functions, rules, data structures, designs and documentation are available in D2F-owned systems.
- **Transfer of paid milestones:** on written acceptance and payment, custom milestone deliverables become D2F property immediately, including source, FlutterFlow work, custom functions, databases/configuration, designs and documentation (subject to third-party licenses).
- **Originality:** custom deliverables must be original or lawfully licensed for the intended use and transfer.
- **Pre-existing developer code:** must be disclosed; D2F receives a **perpetual, worldwide, royalty-free** license to use, reproduce, modify, maintain, distribute and transfer included pre-existing components as part of the D2F platform.
- **Third-party/open-source:** use permitted commercial licenses and provide an inventory of components and obligations; D2F does not gain ownership of other parties’ IP.
- **Confidentiality:** customer, shipping, operational and payment data are used solely for authorized D2F development, testing, operation and support. No unrelated copying, publishing, sale, training or reuse.
- **No unauthorized subcontractors/third-party access:** prior written D2F permission required for any other person or subcontractor to access private code, accounts or customer data.
- **Security incidents:** notify D2F promptly in writing on discovering an actual or reasonably suspected incident; target within approximately **24 hours** where practicable, with containment/cooperation and updates.
- **Access revocation:** D2F can revoke production/developer access upon termination or handover; temporary future support access requires new authorization.
- **Termination:** either party may terminate via written notice. Only completed, demonstrated and **accepted** milestones are payable; unfinished/unaccepted milestones are not automatically owed. D2F keeps all previously paid accepted work and continuous access to its own accounts/data/code. No project, password, record or account may be locked, destroyed, withheld or held as leverage.

## 11. LEGAL AND FORMAL COMMUNICATION TERMS

- Contracting client: **D2F Shipping LLC**. Developer: **Rehan Hamayun** as the contracting individual.
- D2F legal notice address: 2658 N 90th Street, Omaha, NE 68134, USA **subject to D2F confirmation as its legal-notice address**.
- D2F contact email shown: info@d2fshipping.com.
- Developer notice email: rehanhamayun65@gmail.com.
- Formal termination, breach and dispute notices require written notification through confirmed contract-notice channels; approval/rejection can be in email or another mutually recorded written channel.
- **Governing law:** substantive laws of Nebraska, United States, to the extent legally permitted, without ordinary conflict-of-laws application.
- Parties attempt good-faith dispute resolution for **15 calendar days** after written notice.
- If unresolved, proceedings may be brought in a competent court in **Douglas County, Nebraska**, or the **U.S. District Court for the District of Nebraska**, subject to mandatory jurisdiction/procedures.
- Mandatory payment, banking, remittance, dispute/chargeback and other non-waivable legal rights are not waived by the contract text.
- Signatures, authorized signatory details and formal company address should be verified from the executed document where legal certainty is required. Do not claim a draft is signed solely because it is labeled final or ready for signature.

## 12. D2F-PAID THIRD-PARTY COSTS AND MVP EXCLUSIONS

### Normal external service costs paid by D2F

- FlutterFlow subscription where applicable.
- Firebase/Google Cloud hosting, usage, storage and any necessary billing plan.
- Google Play Console registration and business/platform fees.
- Domain, hosting, printing hardware/consumables and other operational services where applicable.
- Meta WhatsApp business messaging usage fees, verification/provider costs where applicable.
- Stock/purchases and operational costs for any selected revenue module.

### Outside the $2,000 fixed MVP unless separately agreed

- Live online payments or cards/ACH/Mobile Money processing; payment webhooks, refunds and advanced automated pricing/rate engine.
- Complex offline-first warehouse engine, advanced sync/conflict management beyond explicitly approved MVP behavior.
- Fully multi-tenant SaaS onboarding, automatic recurring subscription billing and organization-level SaaS commercial system.
- D2F Trade, D2F China, full multi-vendor marketplaces, seller storefronts, carts/checkouts and automated settlement.
- Advanced driver/carrier route planning, continuous live GPS tracking and sophisticated dispatcher optimization.
- Full WhatsApp chatbot or shared omnichannel customer-service inbox.
- Automated external carrier/customs/ERP integrations and advanced partner portals.
- Guaranteed Google approval date or guaranteed Meta template/account approval date.
- iOS App Store release, unless separately commissioned in writing.
- The two **unselected** basic monetization options and expanded features beyond the chosen pair.

## 13. FUTURE ROADMAP — PLANNING ONLY, NOT CURRENT $2,000 DELIVERABLES

D2F has considered developing an extensible logistics network and commercial platform after the shipping MVP. Possible future product tracks:

1. **Advanced Offline & Warehouse Operations:** durable device sync, scan queues, reconciliation, barcode/label hardware integrations and enhanced warehouse controls.
2. **Online Payments & Rate Engine:** card/ACH/Mobile Money gateways, payment reconciliation, refunds, automated rates and service pricing.
3. **Business / Freight Forwarder Portal:** B2B client accounts, volume services, quotations and business-specific operations.
4. **Country Partner / Integrator Portal:** third-party agents, regional warehouses, delegated operations and partner data exchange.
5. **Advanced Driver / Carrier Platform:** richer driver marketplace, route management, tracking, assignments, carrier commercial functions and potential automatic settlement.
6. **Admin, Reporting & Notification Improvements:** analytics, operational KPIs, advanced communication workflows and dashboards.
7. **Multi-Tenant SaaS:** self-service organization/company onboarding, strict tenant isolation, subscription billing and tenant-level settings.
8. **D2F Trade, D2F China and expanded marketplaces:** separate trade/commercial modules, subject to their own discovery, cost and contract.

The MVP should avoid needless architectural barriers to these extensions, but future readiness does **not** justify silently enlarging the current fixed-price deliverables.

## 14. CLIENT DETAILS AND BUSINESS-RULE DECISIONS TO CLARIFY

These are details needed for correct interpretation, **not a progress report**:

- Which **two monetization modules** D2F selects in writing (A/B/C/D). Buy For Me + Sponsored Placements are a recommendation only.
- Official D2F logo, brand palette, app name, splash assets and preferred design direction.
- Actual printer make/model, physical 4×6 example, fields required on labels and printer connectivity type.
- Operational shipment/status permissions in Omaha and Lomé; difference between Released and Delivered; how exceptional shipments are handled.
- Detailed Togo Load Board posting eligibility, assignment/approval process, cancellations and permitted driver statuses.
- Air Traveller participant verification, baggage restriction, custody/hand-off and any regulatory rules beyond the lean capacity module.
- Invoice template, currencies, tax treatment, rates/discounts and which approved staff may record manual payments.
- Pickup request fulfillment rules, driver proof-of-delivery fields, and when a recipient can view tracking.
- Meta Business account and business phone, required opt-in/templates, Google Play Console and Firebase/FlutterFlow admin account access.
- Which low-connectivity actions must work offline within the agreed MVP, if any. Do not assume full offline sync.
- Confirm legal-notice address, authorized D2F signing contact and formal approvals.

## 15. INSTRUCTIONS FOR ANY NEW AI WORKING ON D2F

**Keep the following as stable guiding context:**

1. This is the complete **D2F Shipping $2,000 fixed-price logistics MVP**, not only a UI redesign, a scanning prototype or an Air Traveller app.
2. Respect **all four milestone groupings, each $500**, the free first working APK demonstration, written acceptance, client-owned accounts/source and 120-day in-scope defect support.
3. Keep the **entire** core scope: Staff/Warehouse, Customer Android + PWA, Driver/Togo Load Board, Admin, parcels/barcodes, 4×6 labels, containers/manifests, Omaha/Lomé freight, invoice/manual payments, Air Traveller and WhatsApp API.
4. Include **exactly two client-selected basic commercial modules out of the four offered** within the same $2,000 price; do not misinterpret the four-option menu as four included implementations. Do not treat the recommended pair as confirmed selection.
5. Do not replace Firebase/FlutterFlow or change account ownership casually. Sensitive transitions and payments must be backend-authorized and auditable.
6. Distinguish **manual invoice payment recording** from an actual online gateway. No payment processor is promised for this MVP.
7. Do not confuse future SaaS/Trade or advanced offline/driver features with current contractual features.
8. Ask the client to settle essential missing operational rules before creating irreversible behavior, while using this document for all already specified business objectives and scope.
9. Do not assert a feature, milestone, payment, publication or QA check is complete based solely on this document. It is project requirements/context, not evidence of execution.
10. If a signed contract or later explicit written D2F instruction conflicts with these notes, follow the authoritative document and flag the conflict instead of inventing a resolution.

---

**End of D2F Shipping master project memory.**
