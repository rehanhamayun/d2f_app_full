# D2F Global — Shipping Platform

Unified logistics platform for **D2F Shipping LLC** (Omaha, NE → Lomé, Togo):
Flutter staff/customer/driver app + shared custom backend.

> This build implements **Milestone 1** — Working Android APK and Staff Parcel
> Foundation (staff login, parcel registration with UUID + public tracking ID,
> QR/barcode generation, camera scan + manual lookup, server-persisted event
> history).

## Architecture

```
d2f_application/
├── lib/                  # Flutter app (Android for M1)
│   ├── core/             # theme, API client (dio + JWT)
│   ├── models/           # User / Customer / Parcel / TrackingEvent
│   ├── providers/        # auth session (Riverpod)
│   ├── screens/          # splash, login, staff shell (4 tabs), parcels flow
│   └── widgets/          # shared design-system widgets + timeline
├── backend/              # Node.js + Express + Prisma + PostgreSQL (custom, NOT Firebase)
│   ├── prisma/schema.prisma
│   ├── prisma/seed.js    # staff/admin users, customers, sample parcels
│   └── src/              # routes: auth, parcels (register/list/detail/events), customers
└── design/screens/       # approved UI reference PNGs + project memory MD
```

**Backend data model (M1 subset):** organizations, locations, users (roles),
customers, parcels (UUID + unique `D2F-YYYY-NNNNNN` tracking ID),
`trackingIndex` (public ID → parcel lookup), timestamped tracking events
(actor + location + note), audit log. Status transitions are **forward-only
and validated server-side**; parcel creation is **idempotent** via
`clientRequestId` (retry-safe).

## Quick start (local development)

### 1. Database (PostgreSQL via Docker)

> Uses port **5434** so it coexists with other local Postgres containers.

```bash
cd backend
docker run -d --name d2f-postgres \
  -e POSTGRES_USER=d2f -e POSTGRES_PASSWORD=d2f_dev_password \
  -e POSTGRES_DB=d2f_shipping -p 5434:5432 postgres:16-alpine
```

### 2. Backend API

```bash
cd backend
npm install
npx prisma migrate dev      # apply schema
npx prisma db seed          # users, customers, sample parcels
npm run dev                 # API on http://localhost:4000
```

Health check: `curl http://localhost:4000/health`

### 3. Flutter app (Android)

```bash
flutter pub get
flutter run -d <emulator-or-device>
# Release test APK:
flutter build apk --release   # build/app/outputs/flutter-apk/app-release.apk
```

The app defaults to `http://10.0.2.2:4000` (Android-emulator alias for the
host machine). On a **physical phone**, open **Account → Server Connection**
and enter your computer's LAN IP (e.g. `http://192.168.1.42:4000`).

## Demo accounts (seeded)

| Role  | Email                   | Password    |
|-------|-------------------------|-------------|
| STAFF | staff@d2fshipping.com   | `Staff@2026`|
| ADMIN | admin@d2fshipping.com   | `Admin@2026`|

## Milestone 1 acceptance flow

1. Install APK on a real Android phone → open.
2. Sign in as Staff (`staff@d2fshipping.com` / `Staff@2026`).
3. Ship tab → fill parcel form (customer dropdown / **Add New**, recipient,
   AIR/SEA/ROAD, package type, weight, notes) → **Save Parcel**.
4. Success screen shows the new **D2F-2026-XXXXXX** tracking ID + QR + barcode.
5. Home → **Track parcel** → camera-scan the QR (or use manual lookup) →
   parcel detail opens.
6. **Update Status** → choose forward status (Processing → In Transit →
   Arrived → Ready for Pickup → Delivered) with location + note.
7. Close/reopen the app → parcels, statuses and timestamped history persist
   (PostgreSQL + server events, not local storage).

## Notes / decisions

- Backend is **custom (Node/Express/Prisma/Postgres)** per developer decision —
  the original project memory specified Firebase/FlutterFlow; D2F written
  approval of the architecture change should be recorded.
- `usesCleartextTraffic=true` is enabled **for local demo only** (plain HTTP to
  the dev server). Remove before production / Google Play release.
- The staff dashboard prioritizes M1 registration, scan/manual lookup and parcel
  records. Social sign-in options are explicitly marked as planned. The header
  opens a staff guide; it does not imply a notification service is connected.
- 4×6 label printing, containers/manifests, admin web, invoices/payments,
  Air Traveller and WhatsApp are **Milestone 2–4 scope**.

- Milestone 1 is verified end-to-end on the Android emulator (against the real
  backend, real UI taps): sign-in → dashboard → register parcel (customer +
  recipient + shipment details) → success screen (QR + Code128) → Activity list
  with pull-to-refresh → parcel detail (overview/timeline, forward-only
  "Update Status" with note) → Scan screen (camera preview + manual tracking
  lookup). Release build: `build/app/outputs/flutter-apk/app-release.apk`.


## UI verification

The refreshed staff UI follows the supplied `design/screens` references, with
bundled Plus Jakarta Sans typography and local illustration assets. The backend,
authentication contract, idempotent registration and allowed status transitions
are preserved. Detail tabs switch their content, and the timeline presents actual
recorded events with actor/location/timestamps.

```bash
flutter test
flutter analyze --no-fatal-infos
# Run the real backend before the following emulator journey. It creates a clearly
# labelled demo parcel and records a forward status update in the local database.
flutter build apk --debug --split-per-abi --target-platform android-arm64 -t integration_test/staff_journey_test.dart
flutter drive -d emulator-5554 --use-application-binary=build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk --driver=test_driver/staff_journey_driver.dart --keep-app-running
```

The emulator journey writes screenshots to `design/verification/`. Use
`flutter run -d emulator-5554` for the normal application after testing.
Real-phone installation and physical-label camera scanning remain part of D2F's
M1 acceptance demonstration.


## Hosted M1 test build

The independent mobile test environment is deployed in Railway project
`production_house` (Managing Consultant’s Pro workspace):
`https://d2f-api-production.up.railway.app`.

See `MILESTONE_1_REVIEW.md` for the deliverables/acceptance distinction and
`backend/DEPLOYMENT.md` for deployment details. Private login credentials are in
`.local/TESTING_ACCESS.md` and are excluded from source control. The hosted test
database is separate from local development data. This deployment uses the
existing metered Pro plan, per the updated hosting instruction.

```sh
flutter build apk --release --dart-define=API_BASE_URL=https://d2f-api-production.up.railway.app
```

The supplied `d2f_2.png` / `d2f_3.png` artwork is used for in-app branding and Android
launcher resources. Regenerate launcher sizes with `python3 tool/generate_brand_icons.py`.
