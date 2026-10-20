# Hosted D2F test backend

Project: `production_house` in Managing Consultant’s Projects (Railway Pro).

API: https://d2f-api-production.up.railway.app

Services: `d2f-api` and `Postgres`. PostgreSQL uses a persistent volume. The API connects through the private `Postgres.DATABASE_URL` variable reference. Only the API has a public HTTPS endpoint.

The Docker entrypoint applies checked-in migrations, runs an idempotent seed and starts the API. Production startup requires a JWT secret of at least 32 characters, plus `DEMO_STAFF_PASSWORD` and `DEMO_ADMIN_PASSWORD` for bootstrap test users. Seeding never overwrites existing users’ passwords or parcel history.

The local `.env` is for the local development database and is excluded from deploys. `/.local/` contains private test access and is excluded from Git. Do not commit it.

Deploy from this backend directory:

```sh
railway up --path-as-root . --service d2f-api --detach
railway logs --service d2f-api --lines 100
curl https://d2f-api-production.up.railway.app/health
```

The API health check confirms a database connection. To verify persistence, use a saved tracking ID after restarting the API. Do not run destructive reset/db-push commands against the hosted database.

Resource ceilings: one API replica; API and database each 0.5 vCPU / 0.5 GB RAM. API sleeping is enabled. These are resource limits, not spending caps. Railway usage is metered under the existing Pro subscription.
