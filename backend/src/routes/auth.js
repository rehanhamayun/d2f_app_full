import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { prisma } from '../db.js';
import { JWT_SECRET } from '../config.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { publicUser, sessionFor } from '../auth_session.js';
import { authRateLimit } from '../middleware/auth_rate_limit.js';

const router = Router();
const emailValid = email => typeof email === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim()) && email.length <= 254;
const include = { organization: true, location: true };

router.get('/config', (req, res) => res.json({ registrationVersion: 2, verificationRequired: false }));

router.post('/login', authRateLimit(20), async (req, res, next) => {
  try {
    const { email, password } = req.body || {};
    if (!emailValid(email) || typeof password !== 'string' || !password || Buffer.byteLength(password) > 72) {
      return res.status(400).json({ error: 'Enter a valid email and password (up to 72 bytes)' });
    }
    const user = await prisma.user.findUnique({ where: { email: email.toLowerCase().trim() }, include });
    // A dummy comparison keeps nonexistent-account failures on the same bcrypt path.
    const ok = await bcrypt.compare(password, user?.passwordHash ?? '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy');
    if (!user?.isActive || !ok) return res.status(401).json({ error: 'Invalid email or password, or your account is disabled.' });
    res.json(sessionFor(user));
  } catch (error) { next(error); }
});

router.post('/register', authRateLimit(10), async (req, res, next) => {
  try {
    const { email, password, fullName, phone, role = 'CUSTOMER', invitation } = req.body || {};
    if (!emailValid(email)) return res.status(400).json({ error: 'Enter a valid email address' });
    const emailNorm = email.trim().toLowerCase();
    if (typeof password !== 'string' || password.length < 8 || Buffer.byteLength(password) > 72) {
      return res.status(400).json({ error: 'Password must contain at least 8 characters and at most 72 bytes' });
    }
    if (typeof fullName !== 'string' || !fullName.trim() || fullName.trim().length > 120) {
      return res.status(400).json({ error: 'Enter a name between 1 and 120 characters' });
    }
    if (typeof phone !== 'string' || !/^\+[1-9]\d{7,14}$/.test(phone)) {
      return res.status(400).json({ error: 'Enter a valid international phone number' });
    }
    if (!['CUSTOMER', 'STAFF', 'DRIVER'].includes(role)) {
      return res.status(400).json({ error: 'Choose Customer, Driver or Staff' });
    }
    if (role !== 'CUSTOMER') {
      let invite;
      try { invite = jwt.verify(invitation, JWT_SECRET, { algorithms: ['HS256'] }); } catch { /* Deny below. */ }
      if (invite?.purpose !== 'invitation' || invite.email !== emailNorm || invite.role !== role) {
        return res.status(403).json({ error: 'A valid D2F invitation matching your email and role is required.' });
      }
      // Disabled administrators cannot grant access through outstanding invites.
      const issuer = await prisma.user.findUnique({ where: { id: invite.issuedBy } });
      if (!issuer?.isActive || issuer.role !== 'ADMIN') {
        return res.status(403).json({ error: 'This invitation is no longer valid. Ask your administrator for a new one.' });
      }
    }
    const user = await prisma.user.create({ data: {
      email: emailNorm, passwordHash: await bcrypt.hash(password, 10),
      fullName: fullName.trim(), phone, role, isActive: true,
    }, include });
    res.status(201).json(sessionFor(user));
  } catch (error) {
    if (error?.code === 'P2002') return res.status(409).json({ error: 'An account with this email already exists. Sign in instead.' });
    next(error);
  }
});

// Administrative provisioning is deliberately separate from public registration.
router.post('/invitations', authenticate, requireRole('ADMIN'), async (req, res, next) => {
  try {
    const { email, role } = req.body || {};
    if (!emailValid(email) || !['STAFF', 'DRIVER'].includes(role)) {
      return res.status(400).json({ error: 'A valid email and STAFF or DRIVER role are required.' });
    }
    const invitation = jwt.sign({ purpose: 'invitation', email: email.trim().toLowerCase(), role, issuedBy: req.user.id },
      JWT_SECRET, { expiresIn: '7d', algorithm: 'HS256' });
    res.status(201).json({ invitation, expiresInDays: 7 });
  } catch (error) { next(error); }
});

router.get('/me', authenticate, async (req, res, next) => {
  try {
    const user = await prisma.user.findUnique({ where: { id: req.user.id }, include });
    res.json({ user: publicUser(user) });
  } catch (error) { next(error); }
});

router.patch('/me', authenticate, async (req, res, next) => {
  try {
    const { fullName, phone } = req.body || {};
    if (typeof fullName !== 'string' || !fullName.trim() || fullName.trim().length > 120) {
      return res.status(400).json({ error: 'Enter a name between 1 and 120 characters.' });
    }
    if (phone != null && (typeof phone !== 'string' || phone.length > 40)) {
      return res.status(400).json({ error: 'Enter a valid contact phone number.' });
    }
    const user = await prisma.user.update({ where: { id: req.user.id },
      data: { fullName: fullName.trim(), phone: phone?.trim() || null }, include });
    res.json({ user: publicUser(user) });
  } catch (error) { next(error); }
});
export default router;
