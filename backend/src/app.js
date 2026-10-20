import express from 'express';
import cors from 'cors';
import './config.js';
import { prisma } from './db.js';
import authRouter from './routes/auth.js';
import parcelsRouter from './routes/parcels.js';
import customersRouter from './routes/customers.js';


const app = express();
app.use(cors());
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
app.use('/parcels', parcelsRouter);
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
