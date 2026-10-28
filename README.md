# D2F Global

Android staff shipping app for D2F Shipping LLC, with a shared Express/Prisma/PostgreSQL backend. The repository now includes the Milestone 1 staff parcel foundation and the local Milestone 2 warehouse/admin implementation. Hosted deployments still require the new backend migration and updated clients.

Current Android release: **1.0.7+2011**, including the supplied D2F wordmark launcher icon and updated signup artwork. See [source and build guide](SOURCE_CODE.md) for the repository contents, local setup, and private configuration needed to reproduce a build.

The app defaults to the live HTTPS backend at https://d2f-api-production.up.railway.app, hosted in **production_house**, Managing Consultant’s Railway Pro workspace. It works independently of this development computer. Private account details are in `.local/ACCESS_DETAILS.md` and must not be committed or included in an APK.

## Included

- Reference-based ivory/coral design across welcome, login, signup, role dashboards, shipment registration, activity, tracking, scanning, status updates, profiles, success and label preview. Shared tokens, rounded pastel cards, white outlined fields, navy Plus Jakarta Sans and original reference artwork keep the screens consistent. Auth pages fit without vertical scrolling; splash artwork swipes while text and actions remain fixed.
- Light animated navigation with persistent labels, real API dashboard counts/recents, and separate Customer/Driver workspaces. The FROM/TO card retains typed locations, suggestions, direction swapping and parcel-form prefill in either direction. See [redesign notes and validation](design/reference-redesign-notes.md) for screenshots, asset prompts and live-service limitations.
- Staff/admin sign-in, optional remembered sessions and profile name/contact updates. Roles and account email cannot be edited through the profile API.
- Immediate Customer signup without email/SMS verification. Driver/Staff signup requires an administrator invitation. Separate role landing pages keep operational records restricted to Staff/Admin. Optional Google/Apple sign-in and password recovery are implemented; provider credentials and recovery email delivery require server configuration. See [authentication setup](backend/AUTH_SETUP.md).
- Existing/new customer intake, recipient/route/package details, AIR/SEA/TRAVELER CARGO and notes.
- Customer shipment requests on the shared API: one request may list up to 20 goods lines, attach up to 8 optional goods photos (frozen after warehouse intake, uploaded as raw bytes), and require the recipient's phone/address plus the sender's profile phone. Every request chooses its collection module — **D2F picks up** (collection address + scheduled slot the team confirms and records) or **warehouse drop-off** — and drop-off shipments can never enter the extra `PICKUP_SCHEDULED` → `PICKED_UP` stages added before `RECEIVED`. Staff/admin see the contact phone/email, addresses, goods and photos and move the shipment through mode-aware statuses. See [customer workflow notes](design/customer-workflow-notes.md).
- Permanent parcel UUID and globally unique public tracking ID. New IDs use each organization's reserved 3–5 character uppercase alphanumeric prefix and an isolated 12-digit sequence (for example, `D2F000000000001`). Database reservations retain issued numbers, UUIDs, and prefixes after record deletion. Allocation is transactional and retries are scoped to the organization. Existing tracking IDs remain valid. See [tracking architecture](backend/TRACKING_ARCHITECTURE.md).
- QR/Code128 scanning, manual lookup, real event history with actor/location/time, and server-validated forward status updates.
- 4×6 PDF label preview, Android document save, share and system print/reprint. Both codes use the existing saved tracking identity.
- Marketplace (A) and Buy For Me (D) appear as **Coming soon**, as requested. Commerce workflows are not enabled.

See [MILESTONE_1_REVIEW.md](MILESTONE_1_REVIEW.md) for requirement mapping, validation and acceptance items. The existing Flutter/custom backend architecture differs from the original FlutterFlow/Firebase specification; the client’s written architecture decision still needs to be recorded.

See [MILESTONE_1_CORRECTIONS.md](MILESTONE_1_CORRECTIONS.md) for the response to the 15 review messages, the dependency/security outcome, the assessment-only multi-package, sea-pricing and container-routing options, and the outstanding account-ownership transfer actions.

## Milestone 2

Staff can open **Warehouse & Containers** from Home to create a container, load parcels by saved QR/barcode or manual tracking number, preview/print a manifest, and record departure and arrival. The manifest freezes at departure; loaded parcel progress updates atomically and retains its actor/time/location history. Both EU/USA → Africa and return routes are supported through actual configured facilities.

The web portal adds containers/manifests, locations, account facility assignments, customer profile editing, booking intake, Marketplace products/manual orders and Buy For Me requests/quotes. Authorized Staff dispatchers have an operational workspace; account administration, commerce and location changes remain Admin only. Existing labels, tracking identities and authentication are retained.

See [MILESTONE_2_REVIEW.md](MILESTONE_2_REVIEW.md) for requirements, tests, selected service countries, screenshots, migration and release/acceptance limits. Deploy the backend migration before publishing the new clients. Customer shopping, payment collection and invoice integration are later scope.

## Customer shipment requests

The client's functional workflow reference (in `design/screens/`) is the blueprint for the booking flow: requests are submitted before receipt or pricing, one booking carries multiple goods lines with optional photos, and collection is either staff pickup with a confirmed slot or warehouse drop-off. The implemented contracts — goods lines, photo rules, schedule windows, mode-aware statuses shared by backend, app and admin — are recorded in [design/customer-workflow-notes.md](design/customer-workflow-notes.md), together with the next alignment block (per-package type/dimensions/photos/labels, pickup failure and reschedule reasons, partial-collection discrepancy flags).

## Web Admin dashboard

A separate responsive web Admin dashboard is in [admin-dashboard](admin-dashboard/README.md). It uses the same D2F API, supports live operations and team access management, and includes deployment configuration for Netlify and Cloudflare Pages. Deploy the updated backend before publishing the dashboard; see its README for setup and limitations.

## Run and build

```sh
flutter pub get
flutter run -d emulator-5554
flutter build apk --release --split-per-abi --dart-define=API_BASE_URL=https://d2f-api-production.up.railway.app
```

Private release signing is configured through the ignored `android/key.properties`. Preserve `.local/d2f-release.jks` and its credentials for future updates and transfer them securely to D2F. Without that local configuration, development builds fall back to the debug signer.

Release APKs are split by CPU architecture to avoid bundling unused native libraries. Flutter writes them to `build/app/outputs/flutter-apk/`; copies of this build are in `build/deliverables/`. Install the `arm64-v8a` APK on most modern Android phones; use `armeabi-v7a` for older 32-bit ARM phones or `x86_64` for Android x86 devices. Release traffic uses HTTPS; debug builds retain HTTP support for local development. To replace an older debug-signed build, uninstall that build once before installing this release; server records are retained.

## Local backend development

Use a separate PostgreSQL database. The existing development database is on port 5434. Create `backend/.env` from the example, configure `DATABASE_URL` and a JWT secret, then:

```sh
cd backend
npm ci
npx prisma migrate dev
npx prisma db seed
npm run dev
```

Development seeding includes sample data. Production startup creates organization/locations/bootstrap accounts only; sample shipments require explicit `SEED_DEMO_DATA=true`. Production credentials come from Railway variables and differ from local development defaults.

To use the local API:

```sh
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:4000
```

## Verification

```sh
flutter test
flutter analyze --no-fatal-infos
cd backend && npm test
```

The backend tests use the configured database, create isolated fixtures, and remove only those fixtures. Never point schema resets at the hosted database.

The emulator integration journey uses a private, ignored `.local/hosted-test.json` with the public API URL and a test account password. **Never pass that file to a release build.**

```sh
D2F_SCREENSHOT_DIR=design/verification-v3 flutter drive --profile \
  --driver=test_driver/staff_journey_driver.dart \
  --target=integration_test/staff_journey_test.dart -d emulator-5554 \
  --dart-define-from-file=.local/hosted-test.json
```

Regenerate Android launcher artwork from the supplied originals with `python3 tool/generate_brand_icons.py`. Physical printed-label scanning and printer-specific compatibility still require real hardware acceptance.
