import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { prisma } from '../db.js';

import { JWT_SECRET } from '../config.js';
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
        organizationName: user.organization?.name ?? null,
        locationName: user.location?.name ?? null,
      },
    });
  } catch (e) {
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
        organizationName: user.organization?.name ?? null,
        locationName: user.location?.name ?? null,
      },
    });
  } catch (e) {
    next(e);
  }
});

export default router;
