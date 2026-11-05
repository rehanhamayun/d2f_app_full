-- AlterTable
ALTER TABLE "Product" ADD COLUMN     "status" TEXT NOT NULL DEFAULT 'PENDING_REVIEW';

-- AlterTable
ALTER TABLE "SellerProfile" ADD COLUMN     "termsAccepted" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "verificationStatus" TEXT NOT NULL DEFAULT 'UNVERIFIED';

-- AlterTable
ALTER TABLE "ServiceOrder" ADD COLUMN     "deliveryFeeBps" INTEGER,
ADD COLUMN     "deliveryFeeMinor" INTEGER,
ADD COLUMN     "fulfillmentFeeBps" INTEGER,
ADD COLUMN     "fulfillmentFeeMinor" INTEGER,
ADD COLUMN     "sellerNetMinor" INTEGER;

-- CreateTable
CREATE TABLE "SellerVerification" (
    "id" TEXT NOT NULL,
    "sellerId" TEXT NOT NULL,
    "idDocumentType" TEXT,
    "idDocumentName" TEXT,
    "idDocumentBytes" BYTEA,
    "businessDocName" TEXT,
    "businessDocBytes" BYTEA,
    "selfieBytes" BYTEA,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "reviewNote" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "reviewedById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SellerVerification_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CommissionSettings" (
    "id" TEXT NOT NULL,
    "platformCommissionBps" INTEGER NOT NULL DEFAULT 1000,
    "defaultFulfillmentFeeBps" INTEGER NOT NULL DEFAULT 500,
    "defaultDeliveryFeeBps" INTEGER NOT NULL DEFAULT 300,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "updatedById" TEXT,

    CONSTRAINT "CommissionSettings_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SellerEarnings" (
    "id" TEXT NOT NULL,
    "sellerId" TEXT NOT NULL,
    "grossMerchandiseMinor" INTEGER NOT NULL DEFAULT 0,
    "commissionEarnedMinor" INTEGER NOT NULL DEFAULT 0,
    "fulfillmentFeeEarnedMinor" INTEGER NOT NULL DEFAULT 0,
    "deliveryFeeEarnedMinor" INTEGER NOT NULL DEFAULT 0,
    "netPayableMinor" INTEGER NOT NULL DEFAULT 0,
    "paidOutMinor" INTEGER NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SellerEarnings_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SellerPayout" (
    "id" TEXT NOT NULL,
    "sellerId" TEXT NOT NULL,
    "amountMinor" INTEGER NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "paidAt" TIMESTAMP(3),
    "reference" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SellerPayout_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "SellerVerification_sellerId_key" ON "SellerVerification"("sellerId");

-- CreateIndex
CREATE UNIQUE INDEX "SellerEarnings_sellerId_key" ON "SellerEarnings"("sellerId");

-- AddForeignKey
ALTER TABLE "SellerVerification" ADD CONSTRAINT "SellerVerification_sellerId_fkey" FOREIGN KEY ("sellerId") REFERENCES "SellerProfile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SellerEarnings" ADD CONSTRAINT "SellerEarnings_sellerId_fkey" FOREIGN KEY ("sellerId") REFERENCES "SellerProfile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SellerPayout" ADD CONSTRAINT "SellerPayout_sellerId_fkey" FOREIGN KEY ("sellerId") REFERENCES "SellerProfile"("id") ON DELETE CASCADE ON UPDATE CASCADE;
