-- AlterTable
ALTER TABLE "Product" ADD COLUMN     "featured" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "fulfillment" TEXT NOT NULL DEFAULT 'D2F',
ADD COLUMN     "locationCity" TEXT,
ADD COLUMN     "locationCountry" TEXT,
ADD COLUMN     "sellerId" TEXT,
ADD COLUMN     "stockCount" INTEGER;

-- AlterTable
ALTER TABLE "ServiceOrder" ADD COLUMN     "budgetMinor" INTEGER,
ADD COLUMN     "commissionBps" INTEGER,
ADD COLUMN     "commissionMinor" INTEGER,
ADD COLUMN     "deliveryAddress" TEXT,
ADD COLUMN     "deliveryCity" TEXT,
ADD COLUMN     "deliveryCountry" TEXT,
ADD COLUMN     "deliveryPreference" TEXT,
ADD COLUMN     "recipientName" TEXT,
ADD COLUMN     "recipientPhone" TEXT,
ADD COLUMN     "sellerId" TEXT,
ADD COLUMN     "source" TEXT NOT NULL DEFAULT 'ADMIN',
ADD COLUMN     "trackingRef" TEXT;

-- CreateTable
CREATE TABLE "SellerProfile" (
    "id" TEXT NOT NULL,
    "organizationId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "displayName" TEXT NOT NULL,
    "businessType" TEXT NOT NULL DEFAULT 'INDIVIDUAL',
    "businessName" TEXT,
    "headline" TEXT,
    "bio" TEXT,
    "category" TEXT NOT NULL,
    "phone" TEXT NOT NULL,
    "email" TEXT,
    "country" TEXT NOT NULL,
    "city" TEXT,
    "address" TEXT,
    "commissionBps" INTEGER NOT NULL DEFAULT 1000,
    "termsAcceptedAt" TIMESTAMP(3),
    "reviewNote" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "reviewedById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SellerProfile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ProductImage" (
    "id" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "fileName" TEXT NOT NULL,
    "contentType" TEXT NOT NULL,
    "sizeBytes" INTEGER NOT NULL,
    "bytes" BYTEA NOT NULL,
    "position" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProductImage_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "SellerProfile_userId_key" ON "SellerProfile"("userId");

-- CreateIndex
CREATE INDEX "SellerProfile_organizationId_status_createdAt_idx" ON "SellerProfile"("organizationId", "status", "createdAt");

-- CreateIndex
CREATE INDEX "ProductImage_productId_position_idx" ON "ProductImage"("productId", "position");

-- CreateIndex
CREATE INDEX "Product_organizationId_isActive_category_idx" ON "Product"("organizationId", "isActive", "category");

-- CreateIndex
CREATE INDEX "Product_organizationId_isActive_featured_idx" ON "Product"("organizationId", "isActive", "featured");

-- CreateIndex
CREATE INDEX "Product_sellerId_idx" ON "Product"("sellerId");

-- CreateIndex
CREATE INDEX "ServiceOrder_organizationId_sellerId_createdAt_idx" ON "ServiceOrder"("organizationId", "sellerId", "createdAt");

-- AddForeignKey
ALTER TABLE "SellerProfile" ADD CONSTRAINT "SellerProfile_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SellerProfile" ADD CONSTRAINT "SellerProfile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Product" ADD CONSTRAINT "Product_sellerId_fkey" FOREIGN KEY ("sellerId") REFERENCES "SellerProfile"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ProductImage" ADD CONSTRAINT "ProductImage_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceOrder" ADD CONSTRAINT "ServiceOrder_sellerId_fkey" FOREIGN KEY ("sellerId") REFERENCES "SellerProfile"("id") ON DELETE SET NULL ON UPDATE CASCADE;
