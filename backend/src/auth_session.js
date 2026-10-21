import jwt from 'jsonwebtoken';
import { JWT_SECRET } from './config.js';

export const userSelect = { id: true, email: true, fullName: true, role: true, phone: true,
  organization: { select: { name: true } }, location: { select: { name: true } } };
export function publicUser(user) {
  return { id: user.id, email: user.email, fullName: user.fullName, role: user.role,
    phone: user.phone, organizationName: user.organization?.name ?? null,
    locationName: user.location?.name ?? null };
}
export function sessionFor(user) {
  return { token: jwt.sign({ id: user.id, purpose: 'session', ver: user.authVersion ?? 0 },
    JWT_SECRET, { expiresIn: '12h', algorithm: 'HS256' }), user: publicUser(user) };
}
