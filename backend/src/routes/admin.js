import { Router } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { resolveOrganizationId } from '../tracking.js';

const router = Router();
const userSelect = {
  id: true,
  email: true,
  fullName: true,
  phone: true,
  role: true,
  isActive: true,
  createdAt: true,
  location: { select: { id: true, name: true, code: true } },
};
const shipmentStatuses = [
  'REQUESTED',
  'PICKUP_SCHEDULED',
  'PICKED_UP',
  'RECEIVED',
  'PROCESSING',
  'IN_TRANSIT',
  'ARRIVED_LOME',
  'ARRIVED_DESTINATION',
  'READY_FOR_PICKUP',
  'RELEASED',
  'DELIVERED',
];

function pagination(query) {
  const limit = Number(query.limit ?? 50);
  const offset = Number(query.offset ?? 0);
  if (
    !Number.isSafeInteger(limit) ||
    limit < 1 ||
    limit > 100 ||
    !Number.isSafeInteger(offset) ||
    offset < 0
  ) {
    return null;
  }
  return { limit, offset };
}

router.use(authenticate, requireRole('ADMIN'), async (req, res, next) => {
  try {
    req.organizationId = await resolveOrganizationId(prisma, req.user);
    next();
  } catch (error) {
    next(error);
  }
});

router.get('/overview', async (req, res, next) => {
  try {
    const periodDays = Number(req.query.days ?? 30);
    if (![7, 30, 90].includes(periodDays)) {
      return res.status(400).json({ error: 'Choose a 7, 30, or 90 day period.' });
    }

    const now = new Date();
    const periodStart = new Date(now);
    periodStart.setUTCDate(periodStart.getUTCDate() - periodDays + 1);
    periodStart.setUTCHours(0, 0, 0, 0);
    const chartStart = new Date(periodStart);

    const organizationId = req.organizationId;
    const organizationUsers = await prisma.user.findMany({
      where: { organizationId },
      select: { id: true },
    });
    const [
      totalParcels,
      periodParcels,
      statusGroups,
      methodGroups,
      dailyParcels,
      customerCount,
      userGroups,
      recentEvents,
      recentAudit,
    ] = await prisma.$transaction([
      prisma.parcel.count({ where: { organizationId } }),
      prisma.parcel.count({ where: { organizationId, createdAt: { gte: periodStart } } }),
      prisma.parcel.groupBy({ by: ['status'], where: { organizationId }, _count: { _all: true } }),
      prisma.parcel.groupBy({ by: ['method'], where: { organizationId }, _count: { _all: true } }),
      prisma.parcel.findMany({
        where: { organizationId, createdAt: { gte: chartStart } },
        select: { createdAt: true },
      }),
      prisma.customer.count({ where: { organizationId } }),
      prisma.user.groupBy({
        by: ['role', 'isActive'],
        where: { organizationId },
        _count: { _all: true },
      }),
      prisma.trackingEvent.findMany({
        where: { parcel: { organizationId } },
        orderBy: { createdAt: 'desc' },
        take: 8,
        select: {
          id: true,
          status: true,
          location: true,
          createdAt: true,
          actor: { select: { fullName: true } },
          parcel: {
            select: {
              trackingId: true,
              recipientName: true,
              customer: { select: { displayName: true } },
            },
          },
        },
      }),
      prisma.auditLog.findMany({
        where: { actorId: { in: organizationUsers.map((user) => user.id) } },
        orderBy: { createdAt: 'desc' },
        take: 8,
        select: {
          id: true,
          action: true,
          entity: true,
          entityId: true,
          detail: true,
          createdAt: true,
          actorId: true,
        },
      }),
    ]);
    const auditActorIds = [
      ...new Set(recentAudit.map((entry) => entry.actorId).filter(Boolean)),
    ];
    const auditActors = auditActorIds.length
      ? await prisma.user.findMany({
          where: { id: { in: auditActorIds } },
          select: { id: true, fullName: true },
        })
      : [];
    const actorNames = new Map(auditActors.map((actor) => [actor.id, actor.fullName]));

    const daily = new Map();
    for (const parcel of dailyParcels) {
      const day = parcel.createdAt.toISOString().slice(0, 10);
      daily.set(day, (daily.get(day) ?? 0) + 1);
    }
    const trend = Array.from({ length: periodDays }, (_, index) => {
      const day = new Date(chartStart);
      day.setUTCDate(day.getUTCDate() + index);
      const key = day.toISOString().slice(0, 10);
      return { date: key, count: daily.get(key) ?? 0 };
    });

    const usersByRole = {};
    let totalUsers = 0;
    let activeUsers = 0;
    for (const group of userGroups) {
      usersByRole[group.role] = (usersByRole[group.role] ?? 0) + group._count._all;
      totalUsers += group._count._all;
      if (group.isActive) activeUsers += group._count._all;
    }

    res.json({
      periodDays,
      totalParcels,
      periodParcels,
      customerCount,
      totalUsers,
      activeUsers,
      usersByRole,
      statusCounts: Object.fromEntries(
        statusGroups.map((group) => [group.status, group._count._all]),
      ),
      methodCounts: Object.fromEntries(
        methodGroups.map((group) => [group.method, group._count._all]),
      ),
      parcelTrend: trend,
      recentEvents,
      recentAudit: recentAudit.map((entry) => ({
        ...entry,
        actorName: actorNames.get(entry.actorId) ?? null,
      })),
      generatedAt: now.toISOString(),
    });
  } catch (error) {
    next(error);
  }
});

router.get('/parcels', async (req, res, next) => {
  try {
    const page = pagination(req.query);
    if (!page) {
      return res.status(400).json({ error: 'limit must be 1-100 and offset must be a non-negative integer.' });
    }
    const q = req.query.q?.toString().trim();
    const status = req.query.status?.toString();
    if (status && status !== 'ALL' && !shipmentStatuses.includes(status)) {
      return res.status(400).json({ error: 'Choose a valid shipment status.' });
    }

    const where = {
      organizationId: req.organizationId,
      serviceType: { not: 'AIR_TRAVELLER' },
      ...(status && status !== 'ALL' ? { status } : {}),
      ...(q
        ? {
            OR: [
              { trackingId: { contains: q, mode: 'insensitive' } },
              { recipientName: { contains: q, mode: 'insensitive' } },
              { customer: { is: { displayName: { contains: q, mode: 'insensitive' } } } },
            ],
          }
        : {}),
    };
    const [parcels, total] = await prisma.$transaction([
      prisma.parcel.findMany({
        where,
        include: { customer: { select: { id: true, displayName: true } } },
        orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
        skip: page.offset,
        take: page.limit,
      }),
      prisma.parcel.count({ where }),
    ]);
    res.json({ parcels, total, ...page });
  } catch (error) {
    next(error);
  }
});

router.get('/customers', async (req, res, next) => {
  try {
    const page = pagination(req.query);
    if (!page) {
      return res.status(400).json({ error: 'limit must be 1-100 and offset must be a non-negative integer.' });
    }
    const q = req.query.q?.toString().trim();
    const where = q
      ? {
          organizationId: req.organizationId,
          OR: [
            { displayName: { contains: q, mode: 'insensitive' } },
            { email: { contains: q, mode: 'insensitive' } },
            { phone: { contains: q } },
          ],
        }
      : { organizationId: req.organizationId };
    const [customers, total] = await prisma.$transaction([
      prisma.customer.findMany({
        where,
        orderBy: [{ displayName: 'asc' }, { id: 'asc' }],
        skip: page.offset,
        take: page.limit,
      }),
      prisma.customer.count({ where }),
    ]);
    res.json({ customers, total, ...page });
  } catch (error) {
    next(error);
  }
});

router.get('/users', async (req, res, next) => {
  try {
    const page = pagination(req.query);
    if (!page) {
      return res.status(400).json({ error: 'limit must be 1-100 and offset must be a non-negative integer.' });
    }
    const q = req.query.q?.toString().trim();
    const role = req.query.role?.toString();
    const roles = ['ADMIN', 'STAFF', 'CUSTOMER', 'DRIVER'];
    if (role && role !== 'ALL' && !roles.includes(role)) {
      return res.status(400).json({ error: 'Choose a valid user role.' });
    }

    const where = {
      organizationId: req.organizationId,
      ...(role && role !== 'ALL' ? { role } : {}),
      ...(q
        ? {
            OR: [
              { fullName: { contains: q, mode: 'insensitive' } },
              { email: { contains: q, mode: 'insensitive' } },
            ],
          }
        : {}),
    };
    const [users, total] = await prisma.$transaction([
      prisma.user.findMany({
        where,
        select: userSelect,
        orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
        skip: page.offset,
        take: page.limit,
      }),
      prisma.user.count({ where }),
    ]);
    res.json({ users, total, ...page });
  } catch (error) {
    next(error);
  }
});

router.patch('/users/:id/location', async (req, res, next) => {
  try {
    const { locationId } = req.body || {};
    if (locationId !== null && typeof locationId !== 'string') return res.status(400).json({ error: 'Choose a location or leave the account unassigned.' });
    const updated = await prisma.$transaction(async tx => {
      const user = await tx.user.findFirst({ where: { id: req.params.id, organizationId: req.organizationId } });
      if (!user) return null;
      if (locationId && !await tx.location.findFirst({ where: { id: locationId, organizationId: req.organizationId } })) {
        throw Object.assign(new Error('Location not found in your organization.'), { status: 400 });
      }
      const updated = await tx.user.update({ where: { id: user.id }, data: { locationId }, select: userSelect });
      await tx.auditLog.create({ data: { actorId: req.user.id, action: 'USER_LOCATION_UPDATE', entity: 'User', entityId: user.id, detail: `locationId=${locationId || 'unassigned'}` } });
      return updated;
    });
    if (!updated) return res.status(404).json({ error: 'User not found.' });
    res.json({ user: updated });
  } catch (e) { next(e); }
});

router.patch('/users/:id/active', async (req, res, next) => {
  try {
    const { isActive } = req.body ?? {};
    if (typeof isActive !== 'boolean') {
      return res.status(400).json({ error: 'isActive must be true or false.' });
    }
    if (req.params.id === req.user.id && !isActive) {
      return res.status(400).json({ error: 'You cannot deactivate your own account.' });
    }

    const updated = await prisma.$transaction(
      async (tx) => {
        const target = await tx.user.findFirst({
          where: { id: req.params.id, organizationId: req.organizationId },
          select: { id: true, role: true, isActive: true },
        });
        if (!target) return null;
        if (target.role === 'ADMIN' && target.isActive && !isActive) {
          const activeAdmins = await tx.user.count({
            where: {
              role: 'ADMIN',
              isActive: true,
              organizationId: req.organizationId,
            },
          });
          if (activeAdmins <= 1) {
            const conflict = new Error('The last active administrator cannot be deactivated.');
            conflict.status = 409;
            throw conflict;
          }
        }

        const user = await tx.user.update({
          where: { id: target.id },
          data: { isActive },
          select: userSelect,
        });
        await tx.auditLog.create({
          data: {
            actorId: req.user.id,
            action: isActive ? 'USER_ACTIVATE' : 'USER_DEACTIVATE',
            entity: 'User',
            entityId: user.id,
            detail: `${user.email} (${user.role})`,
          },
        });
        return user;
      },
      { isolationLevel: 'Serializable' },
    );

    if (!updated) return res.status(404).json({ error: 'User not found.' });
    res.json({ user: updated });
  } catch (error) {
    next(error);
  }
});

export default router;
