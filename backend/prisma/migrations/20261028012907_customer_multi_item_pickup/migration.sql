-- AlterTable
ALTER TABLE "Parcel" ADD COLUMN     "deliveryMode" TEXT NOT NULL DEFAULT 'DROP_OFF',
ADD COLUMN     "pickupScheduledAt" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "ParcelItem" (
    "id" TEXT NOT NULL,
    "parcelId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "details" TEXT,
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "weightKg" DOUBLE PRECISION,
    "position" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ParcelItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ParcelImage" (
    "id" TEXT NOT NULL,
    "parcelId" TEXT NOT NULL,
    "fileName" TEXT NOT NULL,
    "contentType" TEXT NOT NULL,
    "sizeBytes" INTEGER NOT NULL,
    "bytes" BYTEA NOT NULL,
    "uploadedById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ParcelImage_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ParcelItem_parcelId_position_idx" ON "ParcelItem"("parcelId", "position");

-- CreateIndex
CREATE INDEX "ParcelImage_parcelId_createdAt_idx" ON "ParcelImage"("parcelId", "createdAt");

-- AddForeignKey
ALTER TABLE "ParcelItem" ADD CONSTRAINT "ParcelItem_parcelId_fkey" FOREIGN KEY ("parcelId") REFERENCES "Parcel"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ParcelImage" ADD CONSTRAINT "ParcelImage_parcelId_fkey" FOREIGN KEY ("parcelId") REFERENCES "Parcel"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ParcelImage" ADD CONSTRAINT "ParcelImage_uploadedById_fkey" FOREIGN KEY ("uploadedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
