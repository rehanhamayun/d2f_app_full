-- AlterTable
ALTER TABLE "Parcel" ADD COLUMN     "deliveryDriverId" TEXT,
ADD COLUMN     "pickupConfirmedAt" TIMESTAMP(3),
ADD COLUMN     "pickupConfirmedById" TEXT,
ADD COLUMN     "pickupDriverId" TEXT,
ADD COLUMN     "pickupPreferredAt" TIMESTAMP(3),
ADD COLUMN     "pickupProofReference" TEXT,
ADD COLUMN     "pickupTargetLocationId" TEXT,
ADD COLUMN     "warehouseReceivedAt" TIMESTAMP(3),
ADD COLUMN     "warehouseReceivedById" TEXT;

-- AlterTable
ALTER TABLE "ParcelItem" ADD COLUMN     "warehouseReceivedAt" TIMESTAMP(3);

-- Preserve the customer's original preferred slot separately from dispatch confirmation.
UPDATE "Parcel" SET "pickupPreferredAt" = "pickupScheduledAt" WHERE "deliveryMode" = 'PICKUP';
UPDATE "Parcel" SET "pickupScheduledAt" = NULL WHERE "deliveryMode" = 'PICKUP' AND "status" = 'REQUESTED';
-- Historical tracking events, custody claims and tracking identifiers are not rewritten.
