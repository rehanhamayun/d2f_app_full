# D2F Global

Android staff shipping app for D2F Shipping LLC, with a shared Express/Prisma/PostgreSQL backend. This build covers the Milestone 1 staff parcel foundation and the requested UI/label enhancements.

The app defaults to the live HTTPS backend at https://d2f-api-production.up.railway.app, hosted in **production_house**, Managing Consultant’s Railway Pro workspace. It works independently of this development computer. Private account details are in `.local/ACCESS_DETAILS.md` and must not be committed or included in an APK.

## Included

- Two animated splash screens, a sign-in screen that fits without scrolling, bundled Plus Jakarta Sans and the supplied D2F app icons.
- Dark colorful cards, local shipping illustrations, branded app bars and responsive form sections.
- Staff/admin sign-in, optional remembered sessions and profile name/contact updates. Roles and account email cannot be edited through the profile API.
- Existing/new customer intake, recipient/route/package details, AIR/SEA/ROAD and notes.
- Permanent parcel UUID and unique public tracking ID. Transactional registration prevents duplicate parcels on retries.
- QR/Code128 scanning, manual lookup, real event history with actor/location/time, and server-validated forward status updates.
- 4×6 PDF label preview, Android document save, share and system print/reprint. Both codes use the existing saved tracking identity.
- Marketplace (A) and Buy For Me (D) appear as **Coming soon**, as requested. Commerce workflows are not enabled.

See [MILESTONE_1_REVIEW.md](MILESTONE_1_REVIEW.md) for requirement mapping, validation and acceptance items. The existing Flutter/custom backend architecture differs from the original FlutterFlow/Firebase specification; the client’s written architecture decision still needs to be recorded.

## Run and build

```sh
flutter pub get
flutter run -d emulator-5554
flutter build apk --release --dart-define=API_BASE_URL=https://d2f-api-production.up.railway.app
```

Private release signing is configured through the ignored `android/key.properties`. Preserve `.local/d2f-release.jks` and its credentials for future updates and transfer them securely to D2F. Without that local configuration, development builds fall back to the debug signer.

The final universal APK is copied to `build/deliverables/D2F-M1-production_house.apk`. Release traffic uses HTTPS; debug builds retain HTTP support for local development. To replace an older debug-signed build, uninstall that build once before installing this release; server records are retained.

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
