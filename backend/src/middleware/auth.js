import jwt from 'jsonwebtoken';

import { JWT_SECRET } from '../config.js';
import { prisma } from '../db.js';

// Attaches req.user when a valid Bearer token is present.
export async function authenticate(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Missing auth token' });

  try {
    const payload = jwt.verify(token, JWT_SECRET);
    const user = await prisma.user.findUnique({ where: { id: payload.id }, select: {
      id: true, email: true, role: true, fullName: true, organizationId: true, locationId: true, isActive: true,
    } });
    if (!user?.isActive) return res.status(401).json({ error: 'Account disabled or not found' });
    req.user = user;
    next();
  } catch (error) {
    if (!(error instanceof jwt.JsonWebTokenError) && !(error instanceof jwt.TokenExpiredError)) return next(error);
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

// Restricts an endpoint to specific roles.
export function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user) return res.status(401).json({ error: 'Not authenticated' });
    if (!roles.includes(req.user.role)) {
      return res.status(403).json({ error: `Forbidden: requires role ${roles.join(' or ')}` });
    }
    next();
  };
}
