import { Router } from 'express';
import { prisma } from '../db.js';
import { authenticate } from '../middleware/auth.js';
import { listFor, markRead, markAllRead, unreadCount } from '../notifications.js';

const router = Router();
router.use(authenticate);

// Tokens are account-scoped, support multiple devices, and are revoked on logout.
router.put('/devices', async (req, res, next) => {
  try {
    const { token, platform } = req.body || {};
    if (typeof token !== 'string' || token.length < 20 || token.length > 4096 || !['android', 'ios', 'web', 'macos'].includes(platform)) return res.status(400).json({ error: 'Provide a valid device token and platform.' });
    await prisma.pushDevice.upsert({ where: { token }, create: { token, platform, userId: req.user.id }, update: { platform, userId: req.user.id } });
    res.json({ registered: true });
  } catch (error) { next(error); }
});
router.delete('/devices', async (req, res, next) => {
  try {
    if (typeof req.body?.token !== 'string') return res.status(400).json({ error: 'Provide the device token.' });
    await prisma.pushDevice.deleteMany({ where: { token: req.body.token, userId: req.user.id } });
    res.json({ removed: true });
  } catch (error) { next(error); }
});

// Buyer-facing notifications (marketplace, Buy For Me, seller lifecycle).
router.get('/', async (req, res, next) => {
  try {
    const limit = Math.min(Math.max(Number(req.query.limit) || 30, 1), 50);
    const [items, unread] = await Promise.all([
      listFor(req.user.id, limit),
      unreadCount(req.user.id),
    ]);
    res.json({ items, unread });
  } catch (error) {
    next(error);
  }
});

router.get('/unread-count', async (req, res, next) => {
  try {
    const unread = await unreadCount(req.user.id);
    res.json({ unread });
  } catch (error) {
    next(error);
  }
});

router.post('/:id/read', async (req, res, next) => {
  try {
    const notification = await markRead(req.params.id, req.user.id);
    if (!notification) return res.status(404).json({ error: 'Notification not found.' });
    res.json({ notification });
  } catch (error) {
    next(error);
  }
});

router.post('/read-all', async (req, res, next) => {
  try {
    const count = await markAllRead(req.user.id);
    res.json({ count });
  } catch (error) {
    next(error);
  }
});

router.delete('/:id', async (req, res, next) => {
  try {
    const removed = await prisma.notification.deleteMany({ where: { id: req.params.id, userId: req.user.id } });
    if (removed.count === 0) return res.status(404).json({ error: 'Notification not found.' });
    res.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

export default router;
