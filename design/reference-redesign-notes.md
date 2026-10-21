# D2F reference redesign — 21 October 2026

Implemented directly in the existing Flutter app using the five JPEG references in `assets/references/`. Shared styling lives in `lib/core/theme.dart`, `lib/widgets/common.dart`, `lib/widgets/auth_widgets.dart`, `lib/widgets/reference_widgets.dart`, and `lib/widgets/d2f_navigation_bar.dart`.

## Screens and flows

- Splash: original `journey.jpg` artwork, ivory canvas, coral/gold corner shapes, navy wordmark and headline. Three backgrounds swipe horizontally with touch, mouse or trackpad. Text and both authentication actions remain fixed. Startup retains its loading state.
- Login: reference layout, original `login.jpg` artwork, white outlined fields, Remember me, recovery, Google/Apple actions, signup link, preserved autofill and authentication handlers.
- Signup: coordinated wordmark/spacing, reference artwork, coral selected role card, original country picker, password controls, validation and invitation flow. Customer signup remains immediate with no email/SMS verification.
- Staff/Admin: personalized greeting and assigned location, real API totals/status counts, coral/blue/yellow register/scan/search cards, real recent shipment records, error/retry states, method choices and the existing two-way route planner. Returning Home refreshes records.
- Customer: reference dashboard composition, shipping enquiry, public tracking, services marked Coming soon, and customer profile. Staff settings and warehouse metadata are omitted from the customer profile.
- Driver: dispatcher contact, public parcel tracking, account editing and sign-out. No job assignments are fabricated.
- Parcel details: pale blue illustrated tracking summary, blue segmented tabs, actual recorded timeline, pastel information grid, existing update-status action, shipping-label preview and PDF report.
- Registration, customer intake, shipment activity, scanning/manual lookup, status updates, account/edit dialog, parcel success, label preview and access gate inherit the same centralized colors, fields, surfaces, typography and app bars.
- Light bottom navigation has persistent labels, coral active state, animated transitions and role-appropriate labels. Wide browser viewports use a centered 600px maximum app canvas.

## Preservation

This redesign leaves the existing API client, auth provider, domain models, backend auth/parcel routes and Prisma schema byte-for-byte unchanged from the start of this request. The app uses Express/Prisma/PostgreSQL and secure storage, not Firebase. Existing role restrictions, endpoints, stored IDs, label identity, forward status transitions and navigation are retained. Dashboard counts and histories come from the API; sample reference numbers/events are not inserted into the app.

## Validation

- `flutter test`: 47 passed, including the complete customer signup → workspace → profile editing/errors → sign-out → sign-in journey through the actual app root. UI session fixtures are confined to tests.
- `cd backend && npm test`: 17 passed against the configured localhost development database. Tests create and remove only their own records. Includes real registration/login/profile persistence and rejection of customer access to operational records or role/email changes.
- `flutter analyze --no-fatal-infos`: no errors or warnings; seven pre-existing uppercase enum naming infos in the unchanged model file.
- Rendered review images: `design/verification-reference-redesign/`. These captures use explicit test fixtures, never production sample records. Actual screens display API data, loading, empty or error states.
- Existing example PDF restored after PDF regression tests.

## Live service limitations

Read-only check of the configured hosted API: `GET /auth/config` returned HTTP 404 on 21 October 2026. The local auth implementation and tests work, but live customer signup remains gated until the hosted backend is updated. No hosted deployment, schema migration or production record mutation was performed in this redesign. Google/Apple sign-in and recovery delivery retain their existing provider/server configuration requirements. Shopping checkout and driver assignment storage are not implemented by the existing backend. Physical camera scanning and printer compatibility still require device testing.

## Generated assets and final prompts

Built-in `image_gen` mode, transparent backgrounds. Outputs inspected and copied into the app's existing bundled image directory. Existing splash/login/warehouse images were reused unchanged. The generated barcode-like marks below are decorative artwork; operational QR/barcodes still use the saved parcel identity.

### `assets/images/tracking_globe_reference.png`

Final prompt:

> Create one isolated premium shipping illustration asset with transparent background, no words, no text, no letters, no logos, no borders or card UI. Composition: a large luminous pale sky-blue 3D globe behind one realistic golden kraft cardboard shipping box in the foreground, taped top, small white shipping label with abstract black barcode only, coral red loose curved motion accent on the left, tiny navy outline airplane with a short dotted arc curving over the globe. Soft friendly editorial 3D realism, smooth rounded globe with subtle simplified continents, warm daylight, navy and coral accents, crisp fine detail. Front three-quarter view. Box occupies lower center right, globe fills upper background. Whole object fully visible with generous transparent breathing room. Intended as the illustration at the right of a pale blue mobile parcel tracking summary card, light cream app UI, modern D2F Global shipping design. Output square high quality.

### `assets/images/send_parcel_reference.png`

Final prompt:

> Single isolated shipping parcel illustration, transparent background, no UI, no text, no logo. Premium warm photoreal 3D editorial style for a mobile shipping app coral action card. One golden kraft cardboard box, view from above front right three-quarter angle, red coral packing tape crossing top, small white shipping label with abstract black barcode on front. A single broad cream white curved arrow sweeps above box from left to upper right, motion accents cream white. Box warm natural brown, believable corrugated edges, soft studio lighting, crisp detailed object with fully visible clean silhouette. Colorful welcoming premium look matching a friendly D2F shipping app. Subject entirely within frame with modest transparent padding. Square.
