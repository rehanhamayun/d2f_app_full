import express from 'express';
import cors from 'cors';
import './config.js';
import { prisma } from './db.js';
import authRouter from './routes/auth.js';
import parcelsRouter from './routes/parcels.js';
import customerParcelsRouter from './routes/customer_parcels.js';
import customersRouter from './routes/customers.js';
import recoveryRouter from './routes/auth_recovery.js';
import socialRouter from './routes/auth_social.js';
import adminRouter from './routes/admin.js';
import { authenticate } from './middleware/auth.js';
import { authRateLimit } from './middleware/auth_rate_limit.js';


const app = express();
app.set('trust proxy', 1);
const allowedOrigins = (process.env.CORS_ORIGINS || '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);
app.use(
  cors(
    allowedOrigins.length
      ? {
          origin(origin, callback) {
            if (!origin || allowedOrigins.includes(origin)) {
              callback(null, true);
            } else {
              callback(null, false);
            }
          },
        }
      : undefined,
  ),
);
app.disable('x-powered-by');
app.use(express.json({ limit: '64kb' }));

// Health check (no auth)
app.get('/health', async (req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ ok: true, service: 'd2f-backend', database: 'connected' });
  } catch {
    res.status(503).json({ ok: false, service: 'd2f-backend', database: 'unavailable' });
  }
});

app.use('/auth', authRouter);
app.use('/auth/password', recoveryRouter);
app.use('/auth/social', socialRouter);
app.use('/admin', adminRouter);
// Tracking-number possession reveals progress only, never people, contact
// details, internal notes, actor identity, or the staff parcel record.
app.get('/tracking/:trackingId', authenticate, authRateLimit(60), async (req, res, next) => {
  try {
    if (!/^D2F-\d{4}-\d{6}$/.test(req.params.trackingId)) {
      return res.status(400).json({ error: 'Enter a valid D2F tracking number.' });
    }
    const parcel = await prisma.parcel.findUnique({ where: { trackingId: req.params.trackingId },
      select: { trackingId: true, status: true, method: true,
        events: { select: { status: true, createdAt: true }, orderBy: { createdAt: 'asc' } } } });
    if (!parcel) return res.status(404).json({ error: 'No shipment found. Check your tracking number.' });
    res.json(parcel);
  } catch (error) { next(error); }
});
app.use('/parcels', parcelsRouter);
app.use('/customer/parcels', customerParcelsRouter);
app.use('/customers', customersRouter);

// 404
app.use((req, res) => res.status(404).json({ error: 'Not found' }));

// Error handler
app.use((err, req, res, next) => {
  console.error(err);
  const code = err.status || 500;
  res.status(code).json({ error: code >= 500 && process.env.NODE_ENV === 'production' ? 'Internal server error' : err.message || 'Internal server error' });
});

export default app;
