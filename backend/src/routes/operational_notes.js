import { Router } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { resolveOrganizationId } from '../tracking.js';
import { ensureNoteLibrary, CUSTOMER_MESSAGES, validateNoteMeaning } from '../operational_notes.js';
import { fail } from '../warehouse.js';
const router = Router();
router.use(authenticate, requireRole('STAFF', 'ADMIN'));
router.get('/', async (req, res, next) => {
 try {
  const organizationId = await resolveOrganizationId(prisma, req.user);
  await ensureNoteLibrary(prisma, organizationId);
  const status = req.query.status?.toString(), serviceType = req.query.serviceType?.toString();
  res.json(await prisma.operationalNoteTemplate.findMany({ where: { organizationId,
   ...(req.query.all === 'true' && req.user.role === 'ADMIN' ? {} : { isActive: true }),
   ...(status ? { status: { in: [status, 'EXCEPTION'] } } : {}),
   ...(serviceType ? { serviceType: { in: ['ALL', serviceType] } } : {}) }, orderBy: [{ position: 'asc' }, { createdAt: 'asc' }] }));
 } catch (e) { next(e); }
});
async function save(req, res, next) {
 try {
  const organizationId = await resolveOrganizationId(prisma, req.user), b = req.body || {};
  if (!Object.hasOwn(CUSTOMER_MESSAGES, b.status) && b.status !== 'EXCEPTION') fail(400, 'Choose a supported operational status.');
  if (!['ALL','SEA','AIR','AIR_CARGO','AIR_TRAVELLER','ROAD'].includes(b.serviceType) || typeof b.message !== 'string' || !b.message.trim() || b.message.length > 700 || !Number.isSafeInteger(b.position) || b.position < 0 || typeof b.isActive !== 'boolean') fail(400, 'Enter a message, service, order and active setting.');
  validateNoteMeaning(b.message, b.status);
  // Customer-facing tracking always uses factual status copy. Operational
  // details are private; an admin cannot accidentally publish inspection notes.
  const data = { status: b.status, serviceType: b.serviceType, message: b.message.trim(), customerMessage: CUSTOMER_MESSAGES[b.status] || 'D2F recorded a shipment exception for review.', position: b.position, isActive: b.isActive };
  const result = await prisma.$transaction(async tx => {
   const old = req.params.id ? await tx.operationalNoteTemplate.findFirst({ where: { id: req.params.id, organizationId } }) : null;
   if (req.params.id && !old) fail(404, 'Message template not found.');
   const row = old ? await tx.operationalNoteTemplate.update({ where: { id: old.id }, data }) : await tx.operationalNoteTemplate.create({ data: { ...data, organizationId } });
   await tx.auditLog.create({ data: { actorId: req.user.id, action: 'OPERATIONAL_TEMPLATE_SAVED', entity: 'OperationalNoteTemplate', entityId: row.id, detail: JSON.stringify({ before: old, after: row }) } });
   return row;
  }); res.json(result);
 } catch (e) { next(e); }
}
router.post('/', requireRole('ADMIN'), save);
router.patch('/:id', requireRole('ADMIN'), save);
export default router;
