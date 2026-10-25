// All warehouse writes share an organization-scoped transaction lock. This
// serializes scan, unload, departure, arrival and individual status changes.
export async function warehouseLock(tx, organizationId) {
  await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${`warehouse:${organizationId}`}, 0))`;
}
export function fail(status, message) {
  throw Object.assign(new Error(message), { status });
}
export const locationLabel = (location) => [location.city || location.name, location.country].filter(Boolean).join(', ');
export const containerInclude = {
  origin: true, destination: true, _count: { select: { parcels: true } },
};
export async function manifestFor(tx, container) {
  if (container.manifest) return container.manifest;
  const parcels = await tx.parcel.findMany({
    where: { containerId: container.id }, orderBy: { trackingId: 'asc' },
    select: { trackingId: true, recipientName: true, packageType: true, weightKg: true,
      origin: true, destination: true, customer: { select: { displayName: true } } },
  });
  return { code: container.code, method: container.method, sealNumber: container.sealNumber,
    origin: locationLabel(container.origin), destination: locationLabel(container.destination),
    issuedAt: new Date().toISOString(), provisional: container.status === 'LOADING',
    parcelCount: parcels.length, totalWeightKg: Math.round(parcels.reduce((n, p) => n + p.weightKg, 0) * 1000) / 1000,
    parcels };
}
export async function containerAudit(tx, user, containerId, action, detail) {
  await tx.containerEvent.create({ data: { containerId, action, detail, actorName: user.fullName } });
  await tx.auditLog.create({ data: { actorId: user.id, action: `CONTAINER_${action}`, entity: 'Container', entityId: containerId, detail } });
}
