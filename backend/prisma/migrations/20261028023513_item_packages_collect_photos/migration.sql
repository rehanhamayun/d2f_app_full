-- AlterTable
ALTER TABLE "Parcel" ADD COLUMN     "restrictionsAcknowledgedAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "ParcelImage" ADD COLUMN     "itemId" TEXT;

-- AlterTable
ALTER TABLE "ParcelItem" ADD COLUMN     "collectedAt" TIMESTAMP(3),
ADD COLUMN     "heightCm" DOUBLE PRECISION,
ADD COLUMN     "lengthCm" DOUBLE PRECISION,
ADD COLUMN     "notCollectedReason" TEXT,
ADD COLUMN     "packageCode" TEXT,
ADD COLUMN     "type" TEXT NOT NULL DEFAULT 'BOX',
ADD COLUMN     "widthCm" DOUBLE PRECISION;

-- AddForeignKey
ALTER TABLE "ParcelImage" ADD CONSTRAINT "ParcelImage_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "ParcelItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;
