export async function resolveOrganizationId(tx, user) {
  if (user.organizationId) return user.organizationId;
  if (user.locationId) {
    const location = await tx.location.findUnique({
      where: { id: user.locationId },
      select: { organizationId: true },
    });
    if (location) return location.organizationId;
  }

  const organizations = await tx.organization.findMany({
    where: { isActive: true },
    orderBy: { createdAt: 'asc' },
    take: 2,
    select: { id: true },
  });
  if (organizations.length === 1) return organizations[0].id;

  const error = new Error(
    organizations.length
      ? 'Select an organization before creating shipments.'
      : 'No active organization is configured for shipment creation.',
  );
  error.status = 409;
  throw error;
}

/** Reserve the next organization sequence inside the parcel's creation transaction. */
export async function generateTrackingId(tx, organizationId) {
  const [allocation] = await tx.$queryRaw`
    UPDATE "Organization"
    SET "trackingCounter" = "trackingCounter" + 1
    WHERE "id" = ${organizationId} AND "isActive" = true
    RETURNING "trackingPrefix", "trackingCounter" - 1 AS "sequence"
  `;
  if (!allocation) {
    const error = new Error('The parcel organization is missing or inactive.');
    error.status = 409;
    throw error;
  }

  const sequence = allocation.sequence.toString();
  if (allocation.sequence < 1n || sequence.length > 12) {
    const error = new Error('The organization has exhausted its tracking-number range.');
    error.status = 409;
    throw error;
  }
  const trackingSequence = allocation.sequence;
  return {
    organizationId,
    trackingSequence,
    trackingId: `${allocation.trackingPrefix}${sequence.padStart(12, '0')}`,
  };
}
