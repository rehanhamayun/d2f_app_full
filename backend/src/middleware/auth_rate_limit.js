import { createHash } from 'node:crypto';
const windows = new Map();
// Per-process abuse protection; use a shared edge limiter when running replicas.
export function authRateLimit(limit = 10) {
  return (req, res, next) => {
    const now = Date.now();
    if (windows.size > 10000) {
      for (const [key, value] of windows) if (value.until < now) windows.delete(key);
      if (windows.size > 10000) return res.status(429).json({ error: 'Too many requests. Please try again later.' });
    }
    const email = typeof req.body?.email === 'string' ? req.body.email.trim().toLowerCase() : '';
    const keys = [`${req.path}:ip:${req.ip}`, ...(email ? [`${req.path}:email:${createHash('sha256').update(email).digest('hex')}`] : [])];
    for (const key of keys) {
      const value = windows.get(key);
      if (value && value.until > now && value.count >= limit) {
        res.set('Retry-After', String(Math.ceil((value.until - now) / 1000)));
        return res.status(429).json({ error: 'Too many attempts. Please try again in a few minutes.' });
      }
    }
    for (const key of keys) {
      const value = windows.get(key);
      windows.set(key, value && value.until > now ? { ...value, count: value.count + 1 } : { count: 1, until: now + 15 * 60000 });
    }
    next();
  };
}
