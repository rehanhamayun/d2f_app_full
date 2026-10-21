import { Router } from 'express';
import { createHmac, randomInt, randomUUID, timingSafeEqual } from 'node:crypto';
import bcrypt from 'bcryptjs';
import { prisma } from '../db.js';
import { JWT_SECRET } from '../config.js';
import { authRateLimit } from '../middleware/auth_rate_limit.js';

const router = Router();
const hash = (ticket, code) => createHmac('sha256', JWT_SECRET).update(`${ticket}:${code}`).digest('hex');

router.post('/forgot', authRateLimit(5), async (req, res, next) => {
  try {
    const email = typeof req.body?.email === 'string' ? req.body.email.trim().toLowerCase() : '';
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) {
      return res.status(400).json({ error: 'Enter a valid email address.' });
    }
    if (!process.env.RESEND_API_KEY || !process.env.AUTH_FROM_EMAIL) {
      return res.status(503).json({ error: 'Email recovery is not available yet. Contact info@d2fshipping.com for help.' });
    }
    await prisma.passwordReset.deleteMany({ where: { expiresAt: { lt: new Date() } } });
    const user = await prisma.user.findUnique({ where: { email } });
    const id = randomUUID(), code = String(randomInt(100000, 1000000));
    const ticket = await prisma.passwordReset.create({ data: {
      id, userId: user?.isActive ? user.id : null, authVersion: user?.authVersion ?? 0,
      codeHash: hash(id, code), expiresAt: new Date(Date.now() + 10 * 60000),
    } });
    if (user?.isActive) {
      try {
        const response = await fetch('https://api.resend.com/emails', {
          method: 'POST', signal: AbortSignal.timeout(12000),
          headers: { Authorization: `Bearer ${process.env.RESEND_API_KEY}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ from: process.env.AUTH_FROM_EMAIL, to: [email],
            subject: 'Your D2F password reset code',
            text: `Your D2F password reset code is ${code}. It expires in 10 minutes. If you did not request this code, ignore this email. Never share this code.`,
          }),
        });
        if (!response.ok) throw new Error('Email provider rejected recovery delivery');
      } catch (error) {
        // Never expose account existence or a reset code through the response/log.
        console.error('Password recovery delivery failed:', error.name);
        await prisma.passwordReset.delete({ where: { id } });
      }
    }
    res.json({ ticket: ticket.id, message: 'If an active account matches this email, a code has been sent.' });
  } catch (error) { next(error); }
});

router.post('/reset', authRateLimit(20), async (req, res, next) => {
  try {
    const { ticket, code, password } = req.body || {};
    if (typeof ticket !== 'string' || !/^[\da-f-]{36}$/i.test(ticket) || typeof code !== 'string' || !/^\d{6}$/.test(code)) {
      return res.status(400).json({ error: 'Enter a valid 6-digit recovery code.' });
    }
    if (typeof password !== 'string' || password.length < 8 || Buffer.byteLength(password) > 72) {
      return res.status(400).json({ error: 'Use at least 8 characters and at most 72 bytes for your password.' });
    }
    // Claim one of five attempts atomically across concurrent requests.
    const attempt = await prisma.passwordReset.updateMany({
      where: { id: ticket, expiresAt: { gt: new Date() }, attempts: { lt: 5 } },
      data: { attempts: { increment: 1 } },
    });
    const reset = attempt.count ? await prisma.passwordReset.findUnique({ where: { id: ticket } }) : null;
    if (!reset?.userId || !timingSafeEqual(Buffer.from(reset.codeHash, 'hex'), Buffer.from(hash(ticket, code), 'hex'))) {
      return res.status(400).json({ error: 'The code is invalid or expired. Request a new code and try again.' });
    }
    const passwordHash = await bcrypt.hash(password, 10);
    const changed = await prisma.$transaction(async tx => {
      const updated = await tx.user.updateMany({
        where: { id: reset.userId, isActive: true, authVersion: reset.authVersion },
        data: { passwordHash, authVersion: { increment: 1 } },
      });
      if (updated.count) await tx.passwordReset.deleteMany({ where: { userId: reset.userId } });
      return updated.count;
    });
    if (!changed) return res.status(400).json({ error: 'The code has already been used. Request a new code.' });
    res.json({ ok: true });
  } catch (error) { next(error); }
});
export default router;
