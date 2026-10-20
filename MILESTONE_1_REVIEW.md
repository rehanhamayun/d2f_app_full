# D2F Milestone 1 review

Reviewed 20 October 2026 against the Milestone 1 section of `design/screens/D2F_Shipping_Complete_AI_Project_Memory.md`.

## Functional deliverables

| Milestone 1 requirement | Implementation and verification |
| --- | --- |
| Installable Android test APK | Release APK built with the supplied D2F launcher artwork and the hosted HTTPS API address. Emulator installation is checked separately from real-phone acceptance. |
| Staff login and permission-aware access | Staff/admin workspace, persistent session, sign-out and optional remembered sign-in. Failed sign-in retains its form and error. Backend rejects unauthenticated, disabled, customer and driver access to staff parcel/customer endpoints. |
| Parcel intake | Existing/new customer, recipient name/phone/address, package type, positive weight, origin/destination, AIR/SEA/ROAD and notes. Mobile journey exercises Sea selection and the saved parcel. |
| Permanent UUID and unique public D2F tracking ID | Both stored in PostgreSQL. Concurrent registrations receive distinct tracking IDs; concurrent retries of one request return one parcel. |
| QR/barcode, lookup and stored history | QR and Code128 use the saved tracking ID. Camera scanning remains implemented. Manual lookup, detail tabs and forward status updates with actor/location/time are exercised. Concurrent updates cannot add duplicate lifecycle events. Physical optical scanning still requires a phone. |
| Working connected backend | Express/Prisma API and PostgreSQL deployed in Railway project `production_house`, in Managing Consultant’s Pro workspace. The app targets HTTPS and runs independently of the development computer. |

## Hosting

- API: https://d2f-api-production.up.railway.app
- Database: Railway PostgreSQL with a persistent volume and private API-to-database connection.
- Project: https://railway.com/project/1e2a3396-5f6f-4ddc-9a9b-4186cbd49396
- One API replica, API sleeping enabled, API and database each limited to 0.5 vCPU / 0.5 GB RAM.
- This uses the existing **Pro plan**, as subsequently requested. Usage is metered; it is not a free-tier deployment. No plan was upgraded and no billing settings were changed.
- The hosted test database is initialized with demo users/customers/parcels. The local development database remains separate and intact.
- Login details are in `.local/TESTING_ACCESS.md`, excluded from source control and deployment uploads. Signing and database secrets are not included in the APK.

## Evidence

- `flutter test`: compact layout checks at 360dp/412dp and 120% text size, search submission, recorded-event timeline and existing model/status-contract checks.
- `cd backend && npm test`: real local PostgreSQL checks for authentication, role enforcement, concurrent registration/retries and status history. Only the test’s own fixtures are removed.
- `design/verification-v2/hosted-api-check.json`: real hosted HTTPS checks including sign-in, customer creation, parcel registration/retry, status update, history and rejected backward update.
- `design/verification-v2/`: Android captures from the mobile journey against the hosted backend.

## Acceptance still required

The implemented M1 software workflow can be demonstrated. This review does **not** certify client acceptance or payment eligibility. The project memory separately requires:

1. D2F installs and uses the APK on a real Android phone, including scanning a printed parcel QR/barcode.
2. D2F reviews the demonstration and provides affirmative written acceptance.
3. Source/current configuration is handed over in D2F-owned accounts/repository. A D2F-owned GitHub handover has not been verified in this workspace.

The existing project uses Flutter plus a custom Express/PostgreSQL backend. The project memory originally describes FlutterFlow/Firebase; the README already records that the architecture change needs D2F’s written approval. This pass retains the existing architecture.

4×6 printing, containers/manifests, customer/driver portals, invoices/payments, Air Traveller and WhatsApp remain outside M1 and are not represented as working features in this staff build.
