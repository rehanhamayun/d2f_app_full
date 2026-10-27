# D2F Milestone 1 review

Reviewed 20 October 2026 against the Milestone 1 section of `design/screens/D2F_Shipping_Complete_AI_Project_Memory.md` and the UI/label requests in this development session. The post-walkthrough corrections and outstanding ownership/assessment items are recorded in [MILESTONE_1_CORRECTIONS.md](MILESTONE_1_CORRECTIONS.md).

## Software requirements

| M1 deliverable | Implementation |
| --- | --- |
| Installable Android APK | Universal release APK with D2F launcher artwork, bundled fonts, live HTTPS configuration and a private release signing key. |
| Working staff login and permission-aware access | Staff/admin workspace, secure stored session, optional remembered sign-in, sign-out and disabled/non-staff rejection. Failed sign-in keeps its form and error. Roles are enforced on the server. |
| Parcel creation | Existing/new customer, recipient/contact/address, package type, positive weight, AIR/SEA/ROAD, origin/destination and notes. Newly added customers remain selected. |
| Permanent UUID and unique tracking ID | Stored in PostgreSQL. Registration and tracking-number allocation are transactional. Concurrent retries return one parcel; distinct registrations receive unique IDs. |
| QR/barcode, lookup and history | Both codes use the saved tracking ID. Camera scanning and manual lookup are implemented. Recorded events show actor, local time, note and location. Forward transitions are validated server-side; concurrent updates do not duplicate lifecycle events. |
| Connected backend | Live Express/Prisma API with persistent PostgreSQL in Railway project `production_house`, Managing Consultant’s Pro workspace. The mobile app works independently of the development computer. |

## Requested additions delivered in this pass

- Two timed, animated splash designs using the supplied shipping illustrations; artwork preloads before the transition timers start.
- Sign-in fits the screen, including a compact screen with the keyboard open, without a page scroll.
- Dark navy, teal and plum cards, selective raised edges/shadows, colorful branded app bars, shipping images, Material/Cupertino icons and bundled Plus Jakarta Sans.
- Profile displays the signed-in account, assigned organization/location and connection status. Name/contact edits persist; role/email remain protected.
- Marketplace **A** and Buy For Me **D** appear as **Coming soon**. No ordering/payment workflow is presented as functional.
- 4×6 PDF labels can be previewed, saved through Android’s document picker, shared and sent to the system print service. Reprinting keeps the same parcel identity.
- Product-facing development/demo wording removed. Production startup no longer seeds sample customers or shipments.

## Hosting and access

- API: https://d2f-api-production.up.railway.app
- Project: https://railway.com/project/1e2a3396-5f6f-4ddc-9a9b-4186cbd49396
- PostgreSQL has a persistent volume and private API-to-database access; no public database TCP proxy.
- One API replica with sleeping enabled; API/database each have a 0.5 vCPU / 0.5 GB ceiling.
- Uses the existing **Pro subscription**, as requested. Usage is metered; this is not free-tier hosting. No plan upgrade was made.
- Bootstrap development passwords were replaced with private generated credentials. Access: `.local/ACCESS_DETAILS.md`. Private signing credentials: `.local/android-signing.json`. These files and the signing key are excluded from source control, deployments and APK assets.
- Local development data remains separate. Hosted sample/automated-check records are removed after verification; non-test shipments are preserved. A private shipping-data backup is retained in `.local/backups/`.

## Verification

- Flutter model, responsive UI, keyboard fit, tracking-search, recorded-event timeline, splash sequencing, PDF identity/dimensions and Android document-save bridge checks.
- Backend integration checks run inside the Railway API service against real PostgreSQL: authentication, role/disabled-account enforcement, protected profile edits, concurrent intake/retries, unique tracking IDs and atomic status history.
- PDF rendered and visually inspected. Page size is 288×432 points (4×6 inches). Both QR and Code128 were independently decoded to the original tracking number.
- Android emulator journey and screenshots: `design/verification-v3/`. This uses the actual hosted HTTPS backend and creates identifiable QA fixtures.
- `flutter analyze` retains only the existing seven enum-name style notices; no analyzer errors or warnings.

## Acceptance and scope limits

The six M1 software deliverables are implemented. Formal M1 acceptance still requires D2F to install/use the APK on a physical Android phone, scan a printed code, confirm persistence after reopening and provide written acceptance. The emulator cannot certify physical camera/label/printer behavior. Standard PDF/system print support does not certify every thermal printer or direct Bluetooth/ZPL integration.

D2F-owned source/account handover has not been verified. The existing Flutter + custom Express/PostgreSQL architecture differs from the original FlutterFlow/Firebase specification; D2F’s written approval of that architecture change remains to be recorded. This review does not certify payment eligibility or client acceptance.

Containers/manifests, customer/driver portals, admin web, invoices/payments, Air Traveller, WhatsApp and working marketplace commerce remain later scope. The label enhancement was added now at the user’s explicit request.

Local development note: the pre-existing Docker VM reported PostgreSQL file I/O errors during a local rerun. No local database reset or unrelated container restart was performed; the revised backend suite passed against Railway using isolated fixtures that it removed.
