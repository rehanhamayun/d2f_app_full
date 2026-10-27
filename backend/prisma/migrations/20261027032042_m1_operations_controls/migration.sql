-- DropIndex
DROP INDEX "Customer_organizationId_idx";

-- AlterTable
ALTER TABLE "Parcel" ADD COLUMN     "deliveredAt" TIMESTAMP(3),
ADD COLUMN     "deliveredToIdNumber" TEXT,
ADD COLUMN     "deliveredToName" TEXT,
ADD COLUMN     "deliveryProofReference" TEXT,
ADD COLUMN     "deliveryProofType" TEXT,
ADD COLUMN     "pickupAddress" TEXT,
ADD COLUMN     "releasedAt" TIMESTAMP(3),
ADD COLUMN     "releasedToIdNumber" TEXT,
ADD COLUMN     "releasedToName" TEXT;

-- CreateTable
CREATE TABLE "ParcelTransfer" (
    "id" TEXT NOT NULL,
    "parcelId" TEXT NOT NULL,
    "fromLocationId" TEXT,
    "toLocationId" TEXT NOT NULL,
    "actorId" TEXT,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ParcelTransfer_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ParcelTransfer_parcelId_createdAt_idx" ON "ParcelTransfer"("parcelId", "createdAt");

-- AddForeignKey
ALTER TABLE "ParcelTransfer" ADD CONSTRAINT "ParcelTransfer_parcelId_fkey" FOREIGN KEY ("parcelId") REFERENCES "Parcel"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ParcelTransfer" ADD CONSTRAINT "ParcelTransfer_fromLocationId_fkey" FOREIGN KEY ("fromLocationId") REFERENCES "Location"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ParcelTransfer" ADD CONSTRAINT "ParcelTransfer_toLocationId_fkey" FOREIGN KEY ("toLocationId") REFERENCES "Location"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ParcelTransfer" ADD CONSTRAINT "ParcelTransfer_actorId_fkey" FOREIGN KEY ("actorId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
