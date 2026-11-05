import { Router } from 'express';
import { prisma } from '../db.js';
import { authenticate } from '../middleware/auth.js';
import { listFor, markRead, markAllRead, unreadCount } from '../notifications.js';

const router = Router();
router.use(authenticate);

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
