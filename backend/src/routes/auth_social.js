import { Router, urlencoded } from 'express';
import { createHash, createPublicKey, randomBytes } from 'node:crypto';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import { prisma } from '../db.js';
import { sessionFor } from '../auth_session.js';
import { authRateLimit } from '../middleware/auth_rate_limit.js';

const router = Router();
const sha = value => createHash('sha256').update(value).digest('hex');
const random = () => randomBytes(32).toString('base64url');
const providers = {
  google: { authorize: 'https://accounts.google.com/o/oauth2/v2/auth', token: 'https://oauth2.googleapis.com/token',
    keys: 'https://www.googleapis.com/oauth2/v3/certs', issuer: ['https://accounts.google.com', 'accounts.google.com'] },
  apple: { authorize: 'https://appleid.apple.com/auth/authorize', token: 'https://appleid.apple.com/auth/token',
    keys: 'https://appleid.apple.com/auth/keys', issuer: 'https://appleid.apple.com' },
};
function configuration(provider) {
  if (!Object.hasOwn(providers, provider)) return null;
  const clientId = process.env[`${provider.toUpperCase()}_CLIENT_ID`];
  const publicUrl = process.env.AUTH_PUBLIC_URL?.replace(/\/$/, '');
  if (!clientId || !publicUrl || !/^https:\/\//.test(publicUrl)) return null;
  if (provider === 'google' && !process.env.GOOGLE_CLIENT_SECRET) return null;
  if (provider === 'apple' && (!process.env.APPLE_TEAM_ID || !process.env.APPLE_KEY_ID || !process.env.APPLE_PRIVATE_KEY)) return null;
  return { ...providers[provider], clientId, redirectUri: `${publicUrl}/auth/social/${provider}/callback` };
}
function clientSecret(provider, config) {
  if (provider === 'google') return process.env.GOOGLE_CLIENT_SECRET;
  return jwt.sign({}, process.env.APPLE_PRIVATE_KEY.replace(/\\n/g, '\n'), {
    algorithm: 'ES256', keyid: process.env.APPLE_KEY_ID, issuer: process.env.APPLE_TEAM_ID,
    audience: 'https://appleid.apple.com', subject: config.clientId, expiresIn: '5m',
  });
}
const keyCache = new Map();
async function identityToken(provider, config, token, nonce) {
  const decoded = jwt.decode(token, { complete: true });
  if (decoded?.header?.alg !== 'RS256' || typeof decoded.header.kid !== 'string') throw new Error('Invalid identity token');
  let cached = keyCache.get(provider);
  if (!cached || cached.until < Date.now() || !cached.keys.some(key => key.kid === decoded.header.kid)) {
    const response = await fetch(config.keys, { signal: AbortSignal.timeout(10000) });
    if (!response.ok) throw new Error('Could not verify identity');
    cached = { keys: (await response.json()).keys, until: Date.now() + 3600000 };
    keyCache.set(provider, cached);
  }
  const key = cached.keys.find(key => key.kid === decoded.header.kid && key.kty === 'RSA' && (!key.use || key.use === 'sig'));
  if (!key) throw new Error('Unknown identity key');
  const claims = jwt.verify(token, createPublicKey({ key, format: 'jwk' }), {
    algorithms: ['RS256'], issuer: config.issuer, audience: config.clientId,
  });
  if (claims.nonce !== nonce || !claims.sub || !claims.email || ![true, 'true'].includes(claims.email_verified)) {
    throw new Error('A verified provider email is required');
  }
  return claims;
}
router.post('/:provider/start', authRateLimit(15), async (req, res, next) => {
  try {
    const provider = req.params.provider, config = configuration(provider);
    if (!config) return res.status(503).json({ error: `${provider === 'apple' ? 'Apple' : 'Google'} sign-in is not configured yet. Please sign in with your email or create an account.` });
    await prisma.socialLoginFlow.deleteMany({ where: { expiresAt: { lt: new Date() } } });
    const secret = random(), state = random(), nonce = random(), verifier = random();
    const flow = await prisma.socialLoginFlow.create({ data: {
      provider, secretHash: sha(secret), stateHash: sha(state), nonce, verifier,
      expiresAt: new Date(Date.now() + 5 * 60000),
    } });
    const url = new URL(config.authorize);
    const params = { client_id: config.clientId, redirect_uri: config.redirectUri, response_type: 'code',
      scope: provider === 'apple' ? 'name email' : 'openid email profile', state, nonce };
    if (provider === 'apple') params.response_mode = 'form_post';
    else {
      params.code_challenge = createHash('sha256').update(verifier).digest('base64url');
      params.code_challenge_method = 'S256'; params.prompt = 'select_account';
    }
    url.search = new URLSearchParams(params).toString();
    res.json({ id: flow.id, secret, url: url.toString() });
  } catch (error) { next(error); }
});

async function callback(req, res, next) {
  const provider = req.params.provider, config = configuration(provider);
  const input = req.method === 'POST' ? req.body : req.query;
  if (!config || typeof input?.state !== 'string') return res.status(400).send('This sign-in link is invalid. Return to D2F and try again.');
  let flow;
  try {
    flow = await prisma.socialLoginFlow.findUnique({ where: { stateHash: sha(input.state) } });
    if (!flow || flow.provider !== provider || flow.expiresAt < new Date() || flow.status !== 'pending') {
      return res.status(400).send('This sign-in has expired or was already used. Return to D2F and try again.');
    }
    const claimed = await prisma.socialLoginFlow.updateMany({ where: { id: flow.id, status: 'pending' }, data: { status: 'processing' } });
    if (!claimed.count) return res.status(400).send('This sign-in has already been used.');
    if (input.error || typeof input.code !== 'string') throw new Error('Sign-in was cancelled. Please try again.');
    const params = { grant_type: 'authorization_code', code: input.code,
      redirect_uri: config.redirectUri, client_id: config.clientId, client_secret: clientSecret(provider, config) };
    if (provider === 'google') params.code_verifier = flow.verifier;
    const response = await fetch(config.token, { method: 'POST', signal: AbortSignal.timeout(12000),
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(params) });
    if (!response.ok) throw new Error('Provider sign-in failed. Please try again.');
    const claims = await identityToken(provider, config, (await response.json()).id_token, flow.nonce);
    const email = claims.email.trim().toLowerCase();
    let identity = await prisma.socialIdentity.findUnique({ where: { provider_subject: { provider, subject: claims.sub } }, include: { user: true } });
    let user = identity?.user;
    if (!identity) {
      // Never silently link a provider to an existing password/staff account.
      if (await prisma.user.findUnique({ where: { email } })) {
        throw new Error('An account already uses this email. Sign in with your email and password.');
      }
      user = await prisma.user.create({ data: {
        email, fullName: String(claims.name || email.split('@')[0]).slice(0, 120), role: 'CUSTOMER',
        passwordHash: await bcrypt.hash(random(), 10),
        socialIdentities: { create: { provider, subject: claims.sub } },
      } });
    }
    if (!user.isActive) throw new Error('This account is disabled. Contact D2F support.');
    await prisma.socialLoginFlow.update({ where: { id: flow.id }, data: { status: 'completed', userId: user.id } });
    res.set('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'");
    res.set('Cache-Control', 'no-store');
    res.type('html').send('<!doctype html><html><meta name="viewport" content="width=device-width,initial-scale=1"><title>D2F · Signed in</title><body style="font-family:system-ui;background:#f9fbff;color:#061c40;text-align:center;padding:20vh 24px"><h1>You’re signed in.</h1><p>Return to the D2F app to continue.</p></body></html>');
  } catch (error) {
    if (!flow) return next(error);
    const message = error.message?.startsWith('An account already') || error.message?.startsWith('This account') || error.message?.startsWith('Sign-in was cancelled')
      ? error.message : 'Could not verify your sign-in. Please try again.';
    try { await prisma.socialLoginFlow.update({ where: { id: flow.id }, data: { status: 'failed', error: message } }); }
    catch (dbError) { return next(dbError); }
    res.status(400).send('Sign-in could not be completed. Return to the D2F app for details.');
  }
}
router.get('/:provider/callback', callback);
router.post('/:provider/callback', urlencoded({ extended: false, limit: '16kb' }), callback);
router.post('/status', authRateLimit(180), async (req, res, next) => {
  try {
    const { id, secret } = req.body || {};
    if (typeof id !== 'string' || typeof secret !== 'string' || id.length > 50 || secret.length > 100) {
      return res.status(400).json({ error: 'Invalid sign-in session.' });
    }
    const flow = await prisma.socialLoginFlow.findUnique({ where: { id } });
    if (!flow || flow.secretHash !== sha(secret) || flow.expiresAt < new Date() || flow.status === 'used') {
      return res.status(400).json({ error: 'This sign-in has expired. Please try again.' });
    }
    if (flow.status === 'failed') return res.status(400).json({ error: flow.error });
    if (flow.status !== 'completed') return res.json({ pending: true });
    const user = await prisma.user.findUnique({ where: { id: flow.userId }, include: { organization: true, location: true } });
    if (!user?.isActive) return res.status(401).json({ error: 'This account is disabled.' });
    const consumed = await prisma.socialLoginFlow.updateMany({ where: { id, status: 'completed' }, data: { status: 'used' } });
    if (!consumed.count) return res.status(400).json({ error: 'This sign-in was already used.' });
    res.set('Cache-Control', 'no-store').json(sessionFor(user));
  } catch (error) { next(error); }
});
export default router;
