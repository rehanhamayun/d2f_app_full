# Railway backend update — 22 October 2026

The production API is deployed and healthy.

The permanent organization tracking architecture is live in deployment
`2f119b9d-3c09-4611-8704-802be352dd4e` (`SUCCESS`). Startup confirmed that
`20261022203000_organization_tracking_numbers` and
`20261022210000_permanent_tracking_reservations` applied successfully. The active
deployment has `sleepApplication: false`. A native database backup named
`Before permanent tracking architecture 2026-10-22` was confirmed beforehand.

New numbers use reserved organization prefixes and 12-digit isolated counters.
Append-only reservations prevent reuse of tracking numbers, parcel UUIDs, and
prefixes after deletion. Database triggers protect identities and counters;
retry keys are scoped per organization. Legacy identifiers remain supported.
See [tracking architecture](TRACKING_ARCHITECTURE.md).

Live checks passed for health/database connectivity, registration configuration,
staff login/session, dashboard counts, parcel/customer listing, role enforcement,
12-digit and previous 15-digit lookup validation, and an existing legacy
shipment's redacted tracking history. A production verification transaction also
confirmed independent partner sequences, reservation creation, and counter
advancement. Its temporary organizations/users/parcels/reservations were rolled
back, and their absence was verified. No synthetic shipments were left behind.

Release 1.0.6 (base Android build 2010) includes the new signup artwork and layout.
All 27 backend tests and all 59 Flutter tests passed. The analyzer succeeds with
nine existing informational style notices. The backend tests used an isolated
PostgreSQL 16 database because the existing local Docker container reports a
storage I/O error. The temporary database server was stopped after testing;
the Docker database was not reset.

Signed APKs are at `build/deliverables/d2f-1.0.6-{arm64-v8a,armeabi-v7a,x86_64}.apk`.
Version codes, the embedded new artwork, and signature compatibility with 1.0.5
were verified; hashes are in `build/deliverables/d2f-1.0.6-build.json`.
Signup layout checks cover compact screens, enlarged text, and keyboard states.
The reviewed screenshot is `design/verification-auth/03-join-d2f.png`.

The notes below retain the earlier deployment history.

The failed attempts are `8f8b04cb-a116-4bd9-a76b-944e25fc4aa2` (12:42 PKT) and
`9d39cb24-a21b-4853-afb5-ff6385e9557b` (12:47 PKT). The original deployment
`46441dab-3bec-484f-921d-f0ceb376f4a8` remained active during those attempts. At 12:48 PKT, live staff
login, session lookup, dashboard counts, parcel listing and customer listing all
returned HTTP 200. Warm health checks took 0.73–0.80 seconds; the first cold
health request took 11.67 seconds. `/auth/config` still returns HTTP 404, so
customer signup and the newer API flows were unavailable before deployment.

Another upload, `9457881f-ea7a-4db5-adfb-8c1830fa67f1`, failed at 13:23 UTC
(18:23 PKT). On 22 October at 19:16 PKT, an explicit CLI upload was accepted as
deployment `6b0e0c03-465a-497c-b31f-50502074d8e8`, which completed successfully.
Its Docker build used the checked-in
Dockerfile, the startup logs confirmed all migrations were applied, and the API
started. Production verification returned HTTP 200 from `/health` with the
database connected and HTTP 200 from `/auth/config` with
`registrationVersion: 2`. Unauthenticated requests to `/customer/parcels` and
`/admin/users` returned HTTP 401, confirming those protected routes are mounted.
The active deployment has `sleepApplication: false`.

The Docker build also reported three high-severity npm audit findings in the
Prisma CLI configuration dependency chain (`prisma` / `@prisma/config` /
`deepmerge-ts`). npm's suggested fix requires a Prisma major-version upgrade;
no dependency upgrade was included in this release.

The Railway incident page reported build issues during this attempt, but the
deployment progressed and is healthy.

At 19:42 PKT, Admin directory pagination was deployed as
`f308ecdb-21a9-4efb-a31a-312bec30c5f1` (`SUCCESS`). Startup confirmed there were
no pending migrations. Production checks returned HTTP 200 for `/health` and
`/auth/config`; unauthenticated requests to `/admin/parcels`,
`/admin/customers`, and `/admin/users` returned HTTP 401.

The Admin site is now published on Cloudflare Pages:
https://d2f-admin-dashboard.pages.dev/ (project `d2f-admin-dashboard`, production
branch `main`). The deployed login page was checked in a browser. A browser
request from that origin received HTTP 200 from `/auth/config` and HTTP 401 from
the protected Admin overview without a token, confirming cross-origin access
and Admin authentication enforcement.

Railway `CORS_ORIGINS` is set to the exact Pages origin. That variable change
deployed successfully as `78073a8c-f5f4-42a7-af56-abbc5fc65ed7` (`SUCCESS`).
Preflight now returns `Access-Control-Allow-Origin:
https://d2f-admin-dashboard.pages.dev`; an unrelated origin receives no CORS
allow-origin header. The API health check remains HTTP 200.

Authenticated production write workflows were verified in local integration
tests; no synthetic writes were made to the production customer database.

Completed on Railway:

- CLI sign-in restored with user-approved permissions scoped to Managing
  Consultant's Projects and `production_house`.
- Native Postgres volume backup created: `Before D2F backend update 2026-10-22`.
  A fresh native backup, `Before resumed D2F backend update 2026-10-22`, was
  confirmed before retrying. Both backups stay in Railway; no customer database
  was exported locally.
- `d2f-api` is configured with `sleepApplication: false`; the latest successful
  deployment reports this setting.

The release includes role-aware signup, password recovery/provider routes,
authenticated redacted tracking, and customer shipment requests. Migrations add
authentication tables/session fields and the optional customer-account link;
existing records are retained. The Docker startup runs `prisma migrate deploy`
before starting the API. Previously issued sessions must sign in again because
the updated backend requires purpose-scoped session tokens.

Flutter fixes made during validation preserve remembered sessions during network
or server failures, prevent a late rejected restore from clearing a newer login,
and give staff dashboard cards room for enlarged text. UI tests now follow the
existing customer self-service shipment form and scroll status filters before
tapping them.

Validation completed: the latest targeted backend run passed all 19 tests.
The Admin dashboard's Vitest suite passes all 7 tests and its production build
succeeds. Earlier Flutter validation passed all 59 tests.
`flutter analyze --no-fatal-infos` succeeds with nine existing informational
style notices. `prisma validate`, client generation, and `git diff --check` pass.
The backend archive is `build/deliverables/d2f-backend-20261022.tar.gz` at the
repository root; it includes the Dockerfile, locked dependencies, source and
migrations, and excludes secrets and local database files.

Android release 1.0.5 (base build 2009) was built successfully with the hosted API
URL. APK signatures and ABI-specific version codes were verified. Files are in
`build/deliverables/d2f-1.0.5-{arm64-v8a,armeabi-v7a,x86_64}.apk`, with hashes in
`build/deliverables/d2f-1.0.5-build.json`. The new customer API features are
available on the deployed backend.

For future backend releases, run from `backend/`:

```sh
railway up --path-as-root . --service d2f-api --environment production --detach
railway deployment list --service d2f-api --limit 3 --json
railway logs --service d2f-api --lines 100
curl --fail https://d2f-api-production.up.railway.app/health
curl --fail https://d2f-api-production.up.railway.app/auth/config
```

Wait for the deployment to become healthy. Verify migrations, `/health`,
`/auth/config`, and the expected API routes before considering a release live.
Use isolated test records for any production write checks; preserve existing
customer shipments.

Google/Apple login and recovery email additionally require the genuine provider
credentials described in [AUTH_SETUP.md](AUTH_SETUP.md). Local mocked transport
tests do not establish that those external integrations are configured in
production. Review Railway's incident guidance before resuming deployment and
credential changes.
