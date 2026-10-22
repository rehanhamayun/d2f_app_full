# Hosted D2F backend

Project: `production_house` in Managing Consultant’s Projects (Railway Pro).

API: https://d2f-api-production.up.railway.app

Services: `d2f-api` and `Postgres`. PostgreSQL uses a persistent volume. The API connects through the private `Postgres.DATABASE_URL` variable reference. Only the API has a public HTTPS endpoint.

The Docker entrypoint applies checked-in migrations, runs an idempotent seed and starts the API. Production startup requires a JWT secret of at least 32 characters, plus `DEMO_STAFF_PASSWORD` and `DEMO_ADMIN_PASSWORD` for bootstrap accounts. Seeding never overwrites existing users’ passwords or parcel history.

The local `.env` is for the local development database and is excluded from deploys. `/.local/` contains private account access and is excluded from Git. Do not commit it.

Deploy from this backend directory:

```sh
railway up --path-as-root . --service d2f-api --detach
railway logs --service d2f-api --lines 100
curl https://d2f-api-production.up.railway.app/health
```

The API health check confirms a database connection. To verify persistence, use a saved tracking ID after restarting the API. Do not run destructive reset/db-push commands against the hosted database.

Resource ceilings: one API replica; API and database each 0.5 vCPU / 0.5 GB RAM. Keep API sleeping disabled (`sleepApplication: false`) to avoid cold-start delays during app login. These are resource limits, not spending caps. Railway usage is metered under the existing Pro subscription; keeping the API awake can increase usage.

The no-sleep setting was saved on 22 October 2026. The running deployment still uses the old settings until a new deployment succeeds. See [the pending update status](RAILWAY_UPDATE_STATUS.md).


Production seeds create authorized accounts/locations only. `SEED_DEMO_DATA` defaults off. Keep bootstrap passwords strong; seed upserts deliberately do not overwrite an existing account password.

## Android signing

`android/key.properties` references the private `.local/d2f-release.jks`. Both the key and `.local/android-signing.json` are excluded from Git. Preserve and securely transfer them to D2F; future APK updates must use the same signer. The key is a local build artifact and is never uploaded to the backend or bundled in the app. Release builds allow HTTPS traffic; local HTTP is available in debug builds.
