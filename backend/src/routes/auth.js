import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { prisma } from '../db.js';

import { JWT_SECRET } from '../config.js';
import { authenticate } from '../middleware/auth.js';
const TOKEN_TTL = '12h';

const router = Router();

// POST /auth/login — staff/customer/driver sign-in
router.post('/login', async (req, res, next) => {
  try {
    const { email, password } = req.body || {};
    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }

    const user = await prisma.user.findUnique({
      where: { email: String(email).toLowerCase().trim() },
      include: { organization: true, location: true },
    });

    if (!user || !user.isActive) {
      return res.status(401).json({ error: 'Invalid credentials or disabled account' });
    }

    const ok = await bcrypt.compare(password, user.passwordHash);
    if (!ok) return res.status(401).json({ error: 'Invalid credentials' });

    const token = jwt.sign(
      {
        id: user.id,
        email: user.email,
        role: user.role,
        fullName: user.fullName,
        organizationId: user.organizationId,
        locationId: user.locationId,
      },
      JWT_SECRET,
      { expiresIn: TOKEN_TTL }
    );

    res.json({
      token,
      user: {
        id: user.id,
        email: user.email,
        fullName: user.fullName,
        role: user.role,
        phone: user.phone,
        organizationName: user.organization?.name ?? null,
        locationName: user.location?.name ?? null,
      },
    });
  } catch (e) {
    next(e);
  }
});

// POST /auth/register — self-service staff account creation.
// Mirrors login's response shape so clients can auto-sign-in immediately.
router.post('/register', async (req, res, next) => {
  try {
    const { email, password, fullName, phone } = req.body || {};
    const emailNorm = typeof email === 'string' ? String(email).toLowerCase().trim() : '';
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailNorm)) {
      return res.status(400).json({ error: 'Enter a valid email address' });
    }
    if (typeof password !== 'string' || password.length < 8) {
      return res.status(400).json({ error: 'Password must be at least 8 characters' });
    }
    const name = typeof fullName === 'string' ? fullName.trim() : '';
    if (!name || name.length > 120) {
      return res.status(400).json({ error: 'Enter a name between 1 and 120 characters' });
    }
    if (phone != null && (typeof phone !== 'string' || phone.length > 40)) {
      return res.status(400).json({ error: 'Enter a valid phone number' });
    }

    const existing = await prisma.user.findUnique({ where: { email: emailNorm } });
    if (existing) {
      return res.status(409).json({ error: 'An account with this email already exists. Sign in instead.' });
    }

    const passwordHash = await bcrypt.hash(password, 10);
    const user = await prisma.user.create({
      data: {
        email: emailNorm,
        passwordHash,
        fullName: name,
        phone: phone && phone.trim() ? phone.trim() : null,
        role: 'STAFF',
        isActive: true,
      },
      include: { organization: true, location: true },
    });
    if (!user) return res.status(500).json({ error: 'Could not create the account' });

    const token = jwt.sign(
      {
        id: user.id,
        email: user.email,
        role: user.role,
        fullName: user.fullName,
        organizationId: user.organizationId,
        locationId: user.locationId,
      },
      JWT_SECRET,
      { expiresIn: TOKEN_TTL }
    );

    res.status(201).json({
      token,
      user: {
        id: user.id,
        email: user.email,
        fullName: user.fullName,
        role: user.role,
        phone: user.phone,
        organizationName: user.organization?.name ?? null,
        locationName: user.location?.name ?? null,
      },
    });
  } catch (e) {
    if (e?.code === 'P2002') {
      return res.status(409).json({ error: 'An account with this email already exists. Sign in instead.' });
    }
    next(e);
  }
});

// GET /auth/me — session restore: decode token, return fresh user
router.get('/me', async (req, res, next) => {
  try {
    const auth = req.headers.authorization || '';
    const token = auth.startsWith('Bearer ') ? auth.slice(7) : null;
    if (!token) return res.status(401).json({ error: 'Missing auth token' });

    let payload;
    try {
      payload = jwt.verify(token, JWT_SECRET);
    } catch {
      return res.status(401).json({ error: 'Invalid or expired token' });
    }

    const user = await prisma.user.findUnique({
      where: { id: payload.id },
      include: { organization: true, location: true },
    });
    if (!user || !user.isActive) {
      return res.status(401).json({ error: 'Account disabled or not found' });
    }

    res.json({
      user: {
        id: user.id,
        email: user.email,
        fullName: user.fullName,
        role: user.role,
        phone: user.phone,
        organizationName: user.organization?.name ?? null,
        locationName: user.location?.name ?? null,
      },
    });
  } catch (e) {
    next(e);
  }
});

// Only the account owner can update their display name and contact phone.
router.patch('/me', authenticate, async (req, res, next) => {
  try {
    const { fullName, phone } = req.body || {};
    if (typeof fullName !== 'string' || !fullName.trim() || fullName.trim().length > 120)
      return res.status(400).json({ error: 'Enter a name between 1 and 120 characters.' });
    if (phone != null && (typeof phone !== 'string' || phone.length > 40))
      return res.status(400).json({ error: 'Enter a valid contact phone number.' });
    const user = await prisma.user.update({ where: { id: req.user.id },
      data: { fullName: fullName.trim(), phone: phone?.trim() || null }, include: { organization: true, location: true } });
    res.json({ user: { id: user.id, email: user.email, fullName: user.fullName, phone: user.phone, role: user.role,
      organizationName: user.organization?.name ?? null, locationName: user.location?.name ?? null } });
  } catch (error) { next(error); }
});

export default router;
