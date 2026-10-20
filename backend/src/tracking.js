/** Generate an ID while holding a per-year lock in the parcel transaction. */
export async function generateTrackingId(tx) {
  const year = new Date().getUTCFullYear();
  const prefix = `D2F-${year}-`;
  await tx.$executeRaw`SELECT pg_advisory_xact_lock(${year})`;
  const last = await tx.parcel.findFirst({
    where: { trackingId: { startsWith: prefix } },
    orderBy: { trackingId: 'desc' },
    select: { trackingId: true },
  });
  const sequence = last ? Number.parseInt(last.trackingId.slice(prefix.length), 10) : 0;
  return `${prefix}${String(sequence + 1).padStart(6, '0')}`;
}
