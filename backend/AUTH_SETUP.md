# Authentication screens and account roles

The Flutter screens follow the October 21 three-screen reference. The welcome
screen has three horizontal backgrounds and stationary copy/actions. Sign-in
and Join D2F fit the viewport and compact when the keyboard opens.

Registration is immediate. There is no email verification or SMS verification.
Only email/phone format, password length and password confirmation are checked.

## Apply the backend update

Run `npx prisma generate` and `npx prisma migrate deploy` from `backend/` before
starting the updated API. The additive migration creates the recovery and social
identity tables, adds a session version, and changes the default role to CUSTOMER.
Existing accounts and parcel records retain their roles and data. Existing sessions
must sign in once again because session tokens now have an explicit purpose.

For a development database originally created with `prisma db push`, first verify
that its schema matches the original migration, then baseline it with
`npx prisma migrate resolve --applied 20261019221055_init`.

The mobile app checks `/auth/config` before registration. This prevents accidental
registration against the old server, which ignored role selection and created
STAFF accounts. Deploy the updated backend to enable registration on the live URL;
the repository change does not deploy the service by itself.

## Role policy

- CUSTOMER: public signup; redacted tracking progress and account/profile access.
  Booking enquiries open the D2F support email. No operational lists, names,
  addresses, internal notes, or parcel editing are exposed.
- DRIVER: invitation required; driver landing page, tracking and profile access.
  The existing project has no assignment model, so the landing page directs the
  driver to their dispatcher. This update does not invent delivery assignments.
- STAFF: invitation required; existing staff workspace and parcel operations.
- ADMIN: existing provisioned administrators only; cannot be selected at signup.

An authenticated ADMIN can POST `/auth/invitations` with
`{"email":"person@example.com","role":"STAFF"}` (or DRIVER). The response contains
an invitation valid for seven days, bound to that exact email and role. Give it to
the intended teammate. Selecting Staff/Driver at signup prompts for this code.
Deactivating or demoting the issuing administrator invalidates unused invitations.
Backend middleware re-reads the database role on every operational request.

## Optional Google and Apple sign-in

Set the relevant variables from `env.production.example` on the API server.
Register the exact HTTPS callback URL for each provider. Apple requires a Services
ID and a Sign in with Apple private P8 key, Key ID and Team ID.

The app opens the provider's browser flow and polls with a device-only secret.
The callback verifies authorization state, the provider signature, nonce, issuer,
audience, expiry and provider email claim. Google also uses PKCE. Temporary flows
are stored in Postgres, work across API replicas, expire after five minutes, and
can be consumed once. The D2F session token is never placed in a browser URL.

Provider accounts create CUSTOMER accounts. Existing provider identities can sign
in again. An existing password account with the same email is not silently linked;
the user signs in with their password. Staff/Driver invitations are handled only
through the registration form.

Setup references: [Google OIDC](https://developers.google.com/identity/openid-connect/openid-connect)
and [Sign in with Apple](https://developer.apple.com/documentation/signinwithapplerestapi).
No provider credentials are bundled into Flutter. Until configured, the buttons
explain the unavailable service and direct the user to email sign-in.

## Optional password recovery

Set `RESEND_API_KEY` and `AUTH_FROM_EMAIL` to enable delivery through Resend. This
is used only when someone chooses Forgot Password; it never blocks registration.
Codes expire after ten minutes, permit five attempts, are stored as keyed hashes,
and are single-use. Password changes invalidate earlier sessions and other codes.
Unknown email addresses receive the same generic response. Missing delivery
configuration returns an explicit service-unavailable message.

The in-process authentication rate limiter covers login, registration, recovery
and social flows. A shared edge rate limiter is recommended for multi-replica
production deployment.

## Validation

`flutter test` checks compact layouts, keyboards, stationary splash buttons,
role selection, country selection and password validation. Screenshots are written
to `design/verification-auth/`. `cd backend && npm test` runs isolated fixtures
against the configured local database and removes them afterwards. Provider/email
transports are mocked in backend tests; real delivery and provider credentials
must be configured separately for end-to-end external-service validation.
