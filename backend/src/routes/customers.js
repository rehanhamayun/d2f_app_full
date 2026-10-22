import { Router } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { resolveOrganizationId } from '../tracking.js';

const router = Router();

router.use(authenticate, requireRole('STAFF', 'ADMIN'));

// GET /customers?q= — search by name/phone/email
router.get('/', async (req, res, next) => {
  try {
    const q = req.query.q?.toString().trim();
    const organizationId = await resolveOrganizationId(prisma, req.user);
    const where = q
      ? {
          organizationId,
          OR: [
            { displayName: { contains: q, mode: 'insensitive' } },
            { email: { contains: q, mode: 'insensitive' } },
            { phone: { contains: q } },
          ],
        }
      : { organizationId };

    const customers = await prisma.customer.findMany({
      where,
      orderBy: { displayName: 'asc' },
      take: 50,
    });
    res.json(customers);
  } catch (e) {
    next(e);
  }
});

// POST /customers — quick-create from the parcel intake form (STAFF/ADMIN)
router.post('/', requireRole('STAFF', 'ADMIN'), async (req, res, next) => {
  try {
    const { displayName, email, phone, address, city, country } = req.body || {};
    if (!displayName?.trim()) {
      return res.status(400).json({ error: 'displayName is required' });
    }
    if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return res.status(400).json({ error: 'Invalid email format' });
    }

    const organizationId = await resolveOrganizationId(prisma, req.user);
    const customer = await prisma.customer.create({
      data: {
        organizationId,
        displayName: displayName.trim(),
        email: email?.trim().toLowerCase() || null,
        phone: phone?.trim() || null,
        address: address?.trim() || null,
        city: city?.trim() || null,
        country: country?.trim() || null,
      },
    });

    await prisma.auditLog.create({
      data: {
        actorId: req.user.id,
        action: 'CUSTOMER_CREATE',
        entity: 'Customer',
        entityId: customer.id,
        detail: `displayName=${customer.displayName}`,
      },
    });

    res.status(201).json(customer);
  } catch (e) {
    next(e);
  }
});

export default router;
