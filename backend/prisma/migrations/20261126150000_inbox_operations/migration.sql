ALTER TABLE "ParcelItem" ADD COLUMN "verifiedWeightKg" DOUBLE PRECISION;
ALTER TABLE "ConnectTrip" ADD COLUMN "scheduleChange" JSONB;

CREATE TABLE "ConnectPackageReceipt" (
  "assignmentId" TEXT NOT NULL REFERENCES "ConnectAssignment"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "packageCode" TEXT NOT NULL,
  "actorId" TEXT NOT NULL,
  "scannedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY ("assignmentId", "packageCode")
);

-- Backfill codes for legacy stock while preserving codes already on labels
-- and original positions for packages recorded as absent.
WITH numbered AS (
  SELECT i.id, p."trackingId", row_number() OVER (
    PARTITION BY i."parcelId" ORDER BY i.position, i."createdAt", i.id
  ) AS position
  FROM "ParcelItem" i
  JOIN "Parcel" p ON p.id = i."parcelId"
  LEFT JOIN "ConnectBooking" b ON b."parcelId" = p.id
  WHERE p."warehouseReceivedAt" IS NOT NULL OR p."pickupConfirmedAt" IS NOT NULL
    OR b."originReceivedAt" IS NOT NULL
    OR (p."restrictionsAcknowledgedAt" IS NULL AND p.status = 'RECEIVED')
)
UPDATE "ParcelItem" i
SET "packageCode" = n."trackingId" || '-P' || lpad(n.position::text, greatest(2, length(n.position::text)), '0')
FROM numbered n
WHERE i.id = n.id AND i."packageCode" IS NULL AND i."notCollectedReason" IS NULL;
