import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID, generateKeyPairSync } from 'node:crypto';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import app from '../src/app.js';
import { prisma } from '../src/db.js';
import { sessionFor } from '../src/auth_session.js';

test('registration, role invitations, password recovery and provider sign-in', async t => {
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const suffix = randomUUID(), users = [];
  const email = `customer-${suffix}@example.com`, password = 'Development-test-123';
  const originalFetch = globalThis.fetch;
  const originalEnv = Object.fromEntries(['RESEND_API_KEY', 'AUTH_FROM_EMAIL', 'GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET',
    'APPLE_CLIENT_ID', 'APPLE_TEAM_ID', 'APPLE_KEY_ID', 'APPLE_PRIVATE_KEY', 'AUTH_PUBLIC_URL'].map(key => [key, process.env[key]]));
  const request = async (path, data, token) => {
    const response = await originalFetch(`${base}${path}`, {
      method: data ? 'POST' : 'GET', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      ...(data ? { body: JSON.stringify(data) } : {}),
    });
    return { status: response.status, body: await response.json() };
  };
  const input = { email, password, fullName: 'Auth QA Customer', phone: '+22890123456' };
  let customer, admin;
  try {
    const organization = await prisma.organization.findFirstOrThrow();
    admin = await prisma.user.create({ data: { email: `admin-${suffix}@example.com`, fullName: 'Auth QA Admin',
      role: 'ADMIN', passwordHash: await bcrypt.hash(password, 10), organizationId: organization.id } }); users.push(admin.id);
    await t.test('public registration defaults to Customer and never requires email or phone verification', async () => {
      const created = await request('/auth/register', input);
      assert.equal(created.status, 201, JSON.stringify(created.body));
      customer = created.body; users.push(customer.user.id);
      assert.equal(customer.user.role, 'CUSTOMER');
      assert.equal((await request('/auth/me', null, customer.token)).status, 200);
      assert.equal((await request('/parcels', null, customer.token)).status, 403);
      assert.equal((await request('/customers', null, customer.token)).status, 403);
    });
    await t.test('roles cannot be escalated and invitations are email/role bound', async () => {
      for (const role of ['STAFF', 'DRIVER', 'ADMIN']) {
        const rejected = await request('/auth/register', { ...input, email: `${role}-${suffix}@example.com`, role });
        assert.equal(rejected.status, 403, `${role} must require an invitation`);
      }
      assert.equal((await request('/auth/invitations', { email, role: 'STAFF' }, customer.token)).status, 403);
      const driverEmail = `driver-${suffix}@example.com`;
      const invitation = (await request('/auth/invitations', { email: driverEmail, role: 'DRIVER' }, sessionFor(admin).token)).body.invitation;
      assert.ok(invitation);
      assert.equal((await request('/auth/me', null, invitation)).status, 401, 'invites are not session tokens');
      assert.equal((await request('/auth/register', { ...input, email: `other-${suffix}@example.com`, role: 'DRIVER', invitation })).status, 403);
      assert.equal((await request('/auth/register', { ...input, email: driverEmail, role: 'STAFF', invitation })).status, 403);
      const registered = await request('/auth/register', { ...input, email: driverEmail, role: 'DRIVER', invitation });
      assert.equal(registered.status, 201, JSON.stringify(registered.body));
      users.push(registered.body.user.id);
      assert.equal(registered.body.user.role, 'DRIVER');
      assert.equal((await request('/parcels', null, registered.body.token)).status, 403);

      // D2F administrators may create another administrator only through an
      // authenticated, email-bound invitation. Public registration cannot.
      const adminEmail = `invited-admin-${suffix}@example.com`;
      const adminInvitation = (await request('/auth/invitations', { email: adminEmail, role: 'ADMIN' }, sessionFor(admin).token)).body.invitation;
      assert.ok(adminInvitation);
      const invitedAdmin = await request('/auth/register', { ...input, email: adminEmail, role: 'ADMIN', invitation: adminInvitation });
      assert.equal(invitedAdmin.status, 201, JSON.stringify(invitedAdmin.body));
      users.push(invitedAdmin.body.user.id);
      assert.equal(invitedAdmin.body.user.role, 'ADMIN');
      assert.equal((await request('/admin/users', null, invitedAdmin.body.token)).status, 200);
    });
    await t.test('signed-in password changes verify the current password and revoke other sessions', async () => {
      const driverEmail = `driver-${suffix}@example.com`;
      const before = await request('/auth/login', { email: driverEmail, password });
      assert.equal(before.status, 200);
      assert.equal((await request('/auth/password/change', {
        currentPassword: 'wrong-password', newPassword: 'Driver-password-456',
      }, before.body.token)).status, 400);
      assert.equal((await request('/auth/password/change', {
        currentPassword: password, newPassword: password,
      }, before.body.token)).status, 400);
      const changed = await request('/auth/password/change', {
        currentPassword: password, newPassword: 'Driver-password-456',
      }, before.body.token);
      assert.equal(changed.status, 200, JSON.stringify(changed.body));
      assert.ok(changed.body.token);
      assert.equal((await request('/auth/me', null, before.body.token)).status, 401);
      assert.equal((await request('/auth/me', null, changed.body.token)).status, 200);
      assert.equal((await request('/auth/login', { email: driverEmail, password })).status, 401);
      assert.equal((await request('/auth/login', { email: driverEmail, password: 'Driver-password-456' })).status, 200);
    });
    await t.test('duplicate registration and wrong credentials return useful errors', async () => {
      assert.equal((await request('/auth/register', input)).status, 409);
      assert.equal((await request('/auth/login', { email, password: 'wrong-password' })).status, 401);
      assert.equal((await request('/auth/login', { email, password })).status, 200);
    });
    await t.test('customer profile updates persist and cannot alter email or role', async () => {
      const response = await originalFetch(`${base}/auth/me`, {
        method: 'PATCH', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${customer.token}` },
        body: JSON.stringify({ fullName: 'Updated QA Customer', phone: '+22890909090', role: 'ADMIN', email: 'cannot-change@example.com' }),
      });
      assert.equal(response.status, 200);
      const updated = (await response.json()).user;
      assert.equal(updated.fullName, 'Updated QA Customer');
      assert.equal(updated.phone, '+22890909090');
      assert.equal(updated.role, 'CUSTOMER');
      assert.equal(updated.email, email);
      const restored = (await request('/auth/me', null, customer.token)).body.user;
      assert.equal(restored.fullName, updated.fullName);
      const signedIn = await request('/auth/login', { email, password });
      assert.equal(signedIn.body.user.fullName, updated.fullName);
      assert.equal(signedIn.body.user.role, 'CUSTOMER');
      const invalid = await originalFetch(`${base}/auth/me`, {
        method: 'PATCH', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${customer.token}` },
        body: JSON.stringify({ fullName: '' }),
      });
      assert.equal(invalid.status, 400);
    });
    await t.test('recovery reports unavailable delivery configuration without pretending to send', async () => {
      delete process.env.RESEND_API_KEY;
      assert.equal((await request('/auth/password/forgot', { email })).status, 503);
    });
    await t.test('recovery codes are single-use and revoke existing sessions', async () => {
      process.env.RESEND_API_KEY = 'test-key'; process.env.AUTH_FROM_EMAIL = 'test@example.com';
      let delivered;
      globalThis.fetch = async (url, options) => {
        if (url === 'https://api.resend.com/emails') { delivered = JSON.parse(options.body); return new Response('{}', { status: 200 }); }
        return originalFetch(url, options);
      };
      const forgot = await request('/auth/password/forgot', { email });
      assert.equal(forgot.status, 200);
      assert.equal(forgot.body.code, undefined);
      const code = delivered.text.match(/\b\d{6}\b/)[0];
      const stored = await prisma.passwordReset.findUnique({ where: { id: forgot.body.ticket } });
      assert.notEqual(stored.codeHash, code);
      assert.equal((await request('/auth/password/reset', { ticket: forgot.body.ticket, code: '000000', password })).status, 400);
      assert.equal((await request('/auth/password/reset', { ticket: forgot.body.ticket, code, password: 'New-password-123' })).status, 200);
      assert.equal((await request('/auth/password/reset', { ticket: forgot.body.ticket, code, password })).status, 400);
      assert.equal((await request('/auth/me', null, customer.token)).status, 401);
      assert.equal((await request('/auth/login', { email, password })).status, 401);
      assert.equal((await request('/auth/login', { email, password: 'New-password-123' })).status, 200);
      const missing = await request('/auth/password/forgot', { email: `unknown-${suffix}@example.com` });
      assert.equal(missing.status, 200);
      await prisma.passwordReset.deleteMany({ where: { id: missing.body.ticket } });
    });
    await t.test('provider configuration is required', async () => {
      delete process.env.GOOGLE_CLIENT_ID;
      assert.equal((await request('/auth/social/google/start', {})).status, 503);
    });
    await t.test('OIDC verifies signatures, state, nonce and polling secret; new users are Customers', async () => {
      process.env.AUTH_PUBLIC_URL = 'https://auth.example.com';
      process.env.GOOGLE_CLIENT_ID = 'test-client'; process.env.GOOGLE_CLIENT_SECRET = 'test-secret';
      const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
      const key = publicKey.export({ format: 'jwk' }); key.kid = 'test-key'; key.alg = 'RS256'; key.use = 'sig';
      const socialEmail = `social-${suffix}@example.com`;
      let nonce, subject = `subject-${suffix}`, providerEmail = socialEmail;
      globalThis.fetch = async (url, options) => {
        if (url === 'https://www.googleapis.com/oauth2/v3/certs') return new Response(JSON.stringify({ keys: [key] }));
        if (url === 'https://oauth2.googleapis.com/token') {
          const params = new URLSearchParams(options.body);
          assert.ok(params.get('code_verifier')); assert.equal(params.get('client_secret'), 'test-secret');
          const token = jwt.sign({ sub: subject, email: providerEmail, email_verified: true, nonce }, privateKey,
            { algorithm: 'RS256', keyid: key.kid, audience: 'test-client', issuer: 'https://accounts.google.com', expiresIn: '5m' });
          return new Response(JSON.stringify({ id_token: token }));
        }
        return originalFetch(url, options);
      };
      const start = async () => {
        const flow = (await request('/auth/social/google/start', {})).body;
        const url = new URL(flow.url); nonce = url.searchParams.get('nonce');
        assert.equal(url.searchParams.get('code_challenge_method'), 'S256');
        return { ...flow, state: url.searchParams.get('state') };
      };
      const flow = await start();
      assert.equal((await request('/auth/social/status', { id: flow.id, secret: 'wrong' })).status, 400);
      assert.equal((await request('/auth/social/status', { id: flow.id, secret: flow.secret })).body.pending, true);
      assert.equal((await originalFetch(`${base}/auth/social/google/callback?state=wrong&code=test`)).status, 400);
      assert.equal((await originalFetch(`${base}/auth/social/google/callback?state=${flow.state}&code=test`)).status, 200);
      const session = await request('/auth/social/status', { id: flow.id, secret: flow.secret });
      assert.equal(session.status, 200, JSON.stringify(session.body)); users.push(session.body.user.id);
      assert.equal(session.body.user.role, 'CUSTOMER');
      assert.equal((await request('/auth/me', null, session.body.token)).status, 200);
      assert.equal((await request('/auth/social/status', { id: flow.id, secret: flow.secret })).status, 400);
      const repeat = await start();
      await originalFetch(`${base}/auth/social/google/callback?state=${repeat.state}&code=test`);
      assert.equal((await request('/auth/social/status', { id: repeat.id, secret: repeat.secret })).body.user.id, session.body.user.id);
      // Provider email collisions must not take over existing password accounts.
      subject = `collision-${suffix}`; providerEmail = admin.email;
      const collision = await start();
      assert.equal((await originalFetch(`${base}/auth/social/google/callback?state=${collision.state}&code=test`)).status, 400);
      const denied = await request('/auth/social/status', { id: collision.id, secret: collision.secret });
      assert.equal(denied.status, 400); assert.match(denied.body.error, /email and password/);
      await prisma.socialLoginFlow.deleteMany({ where: { id: { in: [flow.id, repeat.id, collision.id] } } });
    });
  } finally {
    globalThis.fetch = originalFetch;
    for (const [key, value] of Object.entries(originalEnv)) {
      if (value == null) delete process.env[key]; else process.env[key] = value;
    }
    await prisma.user.deleteMany({ where: { id: { in: users } } });
    await new Promise(resolve => server.close(resolve));
    await prisma.$disconnect();
  }
});
