# D2F Admin Dashboard

Standalone responsive Admin portal for the D2F Global operations API.

Live portal: <https://d2f-admin-dashboard.pages.dev/>

## Capabilities

- Admin and authorized Staff dispatcher sign-in, browser-tab session storage, and automatic logout on expired sessions.
- Shipment overview with live KPI cards, selectable 7/30/90-day shipment activity, status distribution, shipping method comparison, shipment events, and the recent admin audit trail.
- Shipment creation from an existing customer profile, search/filter, shipment detail and event history, and server-validated status transitions.
- Admin shipment corrections: open **Shipments** (or **Bookings**), select a parcel, choose **Edit shipment**, correct its input details and **Save changes**. The form includes customer, recipient name/phone/address, package type, weight, route, method and staff notes; Cancel discards the draft. Corrections preserve the tracking number and status history, record before/after values in the audit trail, and reject stale saves. Staff cannot edit parcel details. Loaded parcels keep their route/method until removed from a loading container or arrival; departure manifests remain frozen. A parcel linked to a shopping order keeps that order's customer.
- Complete shipment, customer-profile, and account directories with server-side search and pagination; counts show how many matching records exist beyond the current page.
- Customer profile creation. This creates a shipping profile, not a customer login account.
- Team account search/filter, staff/driver invitations, and account activation/deactivation. An administrator cannot disable their own account; the API also protects the last active administrator.
- API/database health check and per-browser API-origin override.

All business data comes from the authenticated API. The mobile app and dashboard share the same backend records: staff status updates and customer shipment requests therefore appear in both products when their screens refresh. Shipments created for a profile linked to an app account are visible in that customer's workspace; unlinked profiles remain staff-only. Account activation, invitations, customer profiles, and status changes are persisted server-side and use the API's role checks and audit history. Dashboard pagination retrieves all matching records rather than silently stopping at the app endpoints' original list limits.

Admin also has container loading/manifests, route transitions, facility/time-zone management, account facility assignments, customer profile edits, Marketplace products/manual orders and Buy For Me requests/quotes. Staff dispatchers see only shipment, container, booking and customer operations; management endpoints remain protected.

This is an operations console: it does not change mobile UI or collect payments. Driver assignments and customer shopping are later scope. Status changes must follow the backend's allowed forward transitions. Data is read from the API when a screen loads or refreshes; this is not push/live synchronization.

## Local development

```sh
npm ci
npm run dev
```

Sign in with an active D2F Admin or Staff account. The default API is
`https://d2f-api-production.up.railway.app`; use **Connection settings** on
the sign-in page to point a local build at another API. The dashboard backend
must include `/admin/overview`, `/admin/users`, `/admin/parcels`,
`/admin/customers`, and `/admin/users/:id/active`, as well as the existing
authentication, parcel, customer, and invitation routes.
Parcel editing additionally requires Admin-only `PATCH /parcels/:id` with the
record's `updatedAt` value. Deploy this backend change before the dashboard;
editing itself needs no new database migration beyond the existing schema.

## Test and build

```sh
npm test
npm run build
```

## Netlify deployment

Create a new site using `admin-dashboard` as the base directory. Build command:
`npm run build`; publish directory: `dist`. `netlify.toml` provides SPA routing
and basic security headers. Configure `VITE_API_BASE_URL` as a build environment
variable to set the API origin. Set the backend's `CORS_ORIGINS` variable to a
comma-separated allowlist containing the exact deployed Admin dashboard origin
and any other browser clients that must continue accessing the API.

## Cloudflare Pages deployment

Create a Pages project rooted at `admin-dashboard` with build command
`npm run build` and output directory `dist`. `wrangler.toml`, `_redirects`, and
`_headers` are included. Set `VITE_API_BASE_URL` in the Pages build environment.
For example, with Wrangler:

```sh
npm run build
npx wrangler pages deploy dist --project-name d2f-admin-dashboard
```

The static dashboard can remain available independently of Railway, but all
authentication, charts, shipment updates, and account changes require the
backend to be online and the required Admin routes to be deployed.

## Milestone 2 backend dependency

Deploy the new Prisma migration and backend before this client. New APIs are under `/warehouse` (Staff/Admin), `/warehouse/directory` (paginated Staff operational records), `/admin/commerce` (Admin), `/admin/users/:id/location` (Admin), and `PATCH /customers/:id` (Admin). No automatic connection to the separate d2fshipping.com storefront is configured.

Manifests use authenticated data. Draft previews change while loading; departure saves the final snapshot. Web **Print / Save PDF** opens the system print flow with only the manifest content. Flutter also provides a multipage A4 PDF preview/print/share flow. USB scanners enter tracking IDs into the web load field; Android camera scanning uses the existing mobile scanner.

See [milestone review](../MILESTONE_2_REVIEW.md) for the validated journeys, service-country set and remaining deployment/hardware acceptance work.
