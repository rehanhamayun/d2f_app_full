# D2F staff UI verification — 20 October 2026

The changes follow the supplied design images while prioritizing the Milestone 1 staff parcel foundation documented in the project memory.

## Passed checks

- `flutter test`: 7 tests passed. Includes the existing model/transition tests, search-arrow submission without an external controller, actual-event timeline rendering, and compact layouts at 360dp/412dp with 120% text size.
- `flutter analyze --no-fatal-infos`: no errors or warnings; seven pre-existing enum-name style notices remain in the unchanged model file.
- Android API 36 emulator journey: staff login, Sea-method preset, parcel intake, QR/Code128 generation, detail tabs, forward status update with location/note, manual tracking lookup, refreshed Activity list, Account, and restored application session. All assertions passed against the running local backend.
- Normal release app installed over the test build, force-stopped and reopened: stored staff session restored to the dashboard (see `16-normal-app-running.png`).
- Release build: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (ARM64 Android test build using the repository’s existing signing configuration).

The final local verification parcel is `D2F-2026-000108`: 2.5kg, Sea, Omaha → Lomé, moved from Received to Processing. Verification records are labelled in the recipient/notes and remain in the local demo database. No existing parcel records were deleted or modified by the tests.

The API client, auth provider and model files are unchanged. UI improvements include functional detail tabs, the search submit control, truthful recorded-event history, method preselection and refreshing Activity on entry.

## Review

Open [index.html](index.html) for full emulator captures or [overview.jpg](overview.jpg) for the contact sheet. Screenshots are from the real app, not rendered design mockups.

Physical label scanning and real-phone installation still require a physical-device acceptance check. The camera controller, supported QR/Code128 formats and barcode callback are retained; the emulator test exercises manual lookup.
