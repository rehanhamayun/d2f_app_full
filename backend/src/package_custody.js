import { fail } from './warehouse.js';
export async function recordCollection(tx, parcel, missedItems) {
  if (missedItems != null && !Array.isArray(missedItems)) {
    fail(400, 'missedItems must be an array of { itemId, reason }.');
  }
  const items = await tx.parcelItem.findMany({
    where: { parcelId: parcel.id },
    orderBy: [{ position: 'asc' }, { createdAt: 'asc' }],
  });
  if (!items.length) return null;
  const missed = [];
  if (Array.isArray(missedItems)) {
    for (const entry of missedItems) {
      const itemId = entry?.itemId;
      const reason = typeof entry?.reason === 'string' ? entry.reason.trim() : '';
      if (!items.some((item) => item.id === itemId)) {
        fail(400, 'Every missed package must be one of the goods declared on this shipment.');
      }
      if (!reason || reason.length > 300) {
        fail(400, 'Record why a package was not collected (up to 300 characters).');
      }
      if (missed.some((entry) => entry.itemId === itemId)) {
        fail(400, 'A package was listed more than once in the collection outcome.');
      }
      missed.push({ itemId, reason });
    }
  }
  if (missed.length === items.length) {
    fail(400, 'No packages were collected. Keep the pickup open and record or reschedule the attempt.');
  }
  const collectedAt = new Date();
  for (const item of items) {
    const missedEntry = missed.find((entry) => entry.itemId === item.id);
    await tx.parcelItem.update({
      where: { id: item.id },
      data: missedEntry
        ? { notCollectedReason: missedEntry.reason, collectedAt: null }
        : { notCollectedReason: null, collectedAt },
    });
  }
  return { collected: items.length - missed.length, total: items.length };
}

/** Allocates {@link ParcelItem.packageCode} `TRK-P01…` codes by declared order. */
export async function allocatePackageCodes(tx, parcel) {
  const items = await tx.parcelItem.findMany({
    where: { parcelId: parcel.id },
    orderBy: [{ position: 'asc' }, { createdAt: 'asc' }],
  });
  for (const [index, item] of items.entries()) {
    if (item.packageCode || item.notCollectedReason) continue;
    await tx.parcelItem.update({
      where: { id: item.id },
      data: {
        packageCode: `${parcel.trackingId}-P${String(index + 1).padStart(2, '0')}`,
      },
    });
  }
}
