-- CreateTable
CREATE TABLE "BuyForMeRequest" (
    "id" TEXT NOT NULL,
    "customerId" TEXT NOT NULL,
    "organizationId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "sourceUrl" TEXT,
    "sourceSite" TEXT,
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "budgetMinor" INTEGER,
    "notes" TEXT,
    "productCostMinor" INTEGER,
    "taxMinor" INTEGER,
    "purchasingFeeMinor" INTEGER,
    "shippingFeeMinor" INTEGER,
    "otherChargesMinor" INTEGER,
    "totalQuoteMinor" INTEGER,
    "quoteValidUntil" TIMESTAMP(3),
    "quoteNotes" TEXT,
    "status" TEXT NOT NULL DEFAULT 'REQUESTED',
    "paymentStatus" TEXT NOT NULL DEFAULT 'UNPAID',
    "purchaseDate" TIMESTAMP(3),
    "purchaseReceipt" TEXT,
    "supplierOrderId" TEXT,
    "recipientName" TEXT,
    "recipientPhone" TEXT,
    "recipientAddress" TEXT,
    "recipientCity" TEXT,
    "recipientCountry" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "acceptedAt" TIMESTAMP(3),
    "paidAt" TIMESTAMP(3),
    "shippedAt" TIMESTAMP(3),
    "completedAt" TIMESTAMP(3),
    "parcelId" TEXT,

    CONSTRAINT "BuyForMeRequest_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ShipForMeRequest" (
    "id" TEXT NOT NULL,
    "customerId" TEXT NOT NULL,
    "organizationId" TEXT NOT NULL,
    "warehouseAddressId" TEXT,
    "customerWarehouseId" TEXT,
    "retailerName" TEXT,
    "retailerOrderId" TEXT,
    "retailerTrackingId" TEXT,
    "itemDescription" TEXT,
    "declaredValueMinor" INTEGER,
    "declaredCurrency" TEXT DEFAULT 'USD',
    "packageWeightKg" DOUBLE PRECISION,
    "packageLengthCm" DOUBLE PRECISION,
    "packageWidthCm" DOUBLE PRECISION,
    "packageHeightCm" DOUBLE PRECISION,
    "packagePhotos" TEXT,
    "receivedAt" TIMESTAMP(3),
    "receivedBy" TEXT,
    "packageCondition" TEXT,
    "receivingNotes" TEXT,
    "status" TEXT NOT NULL DEFAULT 'DRAFT',
    "agreementAccepted" BOOLEAN NOT NULL DEFAULT false,
    "agreementVersion" TEXT,
    "acceptedAt" TIMESTAMP(3),
    "shippingFeeMinor" INTEGER,
    "insuranceFeeMinor" INTEGER,
    "handlingFeeMinor" INTEGER,
    "totalQuoteMinor" INTEGER,
    "quoteValidUntil" TIMESTAMP(3),
    "quoteNotes" TEXT,
    "paymentStatus" TEXT NOT NULL DEFAULT 'UNPAID',
    "paidAt" TIMESTAMP(3),
    "shippingMethod" TEXT,
    "carrier" TEXT,
    "carrierTrackingId" TEXT,
    "shippedAt" TIMESTAMP(3),
    "deliveredAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "submittedAt" TIMESTAMP(3),
    "parcelId" TEXT,

    CONSTRAINT "ShipForMeRequest_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "WarehouseAddress" (
    "id" TEXT NOT NULL,
    "organizationId" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "addressLine1" TEXT NOT NULL,
    "addressLine2" TEXT,
    "city" TEXT NOT NULL,
    "stateProvince" TEXT,
    "postalCode" TEXT NOT NULL,
    "country" TEXT NOT NULL,
    "phone" TEXT,
    "email" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "isDefault" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "WarehouseAddress_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CustomerAgreement" (
    "id" TEXT NOT NULL,
    "version" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "serviceType" TEXT NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "effectiveFrom" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CustomerAgreement_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CustomerAgreementAcceptance" (
    "id" TEXT NOT NULL,
    "customerId" TEXT NOT NULL,
    "agreementId" TEXT NOT NULL,
    "version" TEXT NOT NULL,
    "acceptedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "acceptedVia" TEXT,
    "ipAddress" TEXT,

    CONSTRAINT "CustomerAgreementAcceptance_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Payment" (
    "id" TEXT NOT NULL,
    "buyForMeRequestId" TEXT,
    "shipForMeRequestId" TEXT,
    "customerId" TEXT NOT NULL,
    "organizationId" TEXT NOT NULL,
    "amountMinor" INTEGER NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "paymentMethod" TEXT NOT NULL,
    "paymentProvider" TEXT,
    "providerReference" TEXT,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "purpose" TEXT NOT NULL,
    "verificationNotes" TEXT,
    "verifiedBy" TEXT,
    "verifiedAt" TIMESTAMP(3),
    "verificationImage" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "completedAt" TIMESTAMP(3),

    CONSTRAINT "Payment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PaymentMethodConfig" (
    "id" TEXT NOT NULL,
    "organizationId" TEXT NOT NULL,
    "serviceType" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL,
    "method" TEXT NOT NULL,
    "provider" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "minAmountMinor" INTEGER,
    "maxAmountMinor" INTEGER,
    "feePercent" INTEGER DEFAULT 0,
    "feeFixedMinor" INTEGER DEFAULT 0,
    "config" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PaymentMethodConfig_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ReturnRequest" (
    "id" TEXT NOT NULL,
    "buyForMeRequestId" TEXT,
    "shipForMeRequestId" TEXT,
    "customerId" TEXT NOT NULL,
    "organizationId" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "description" TEXT,
    "requestedAmountMinor" INTEGER,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "adminDecision" TEXT,
    "decidedAt" TIMESTAMP(3),
    "decidedBy" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ReturnRequest_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "BuyForMeRequest_customerId_status_createdAt_idx" ON "BuyForMeRequest"("customerId", "status", "createdAt");

-- CreateIndex
CREATE INDEX "BuyForMeRequest_organizationId_status_createdAt_idx" ON "BuyForMeRequest"("organizationId", "status", "createdAt");

-- CreateIndex
CREATE INDEX "ShipForMeRequest_customerId_status_createdAt_idx" ON "ShipForMeRequest"("customerId", "status", "createdAt");

-- CreateIndex
CREATE INDEX "ShipForMeRequest_organizationId_status_createdAt_idx" ON "ShipForMeRequest"("organizationId", "status", "createdAt");

-- CreateIndex
CREATE INDEX "ShipForMeRequest_customerWarehouseId_idx" ON "ShipForMeRequest"("customerWarehouseId");

-- CreateIndex
CREATE INDEX "WarehouseAddress_organizationId_isActive_idx" ON "WarehouseAddress"("organizationId", "isActive");

-- CreateIndex
CREATE UNIQUE INDEX "CustomerAgreement_version_key" ON "CustomerAgreement"("version");

-- CreateIndex
CREATE INDEX "CustomerAgreementAcceptance_customerId_acceptedAt_idx" ON "CustomerAgreementAcceptance"("customerId", "acceptedAt");

-- CreateIndex
CREATE UNIQUE INDEX "CustomerAgreementAcceptance_customerId_agreementId_key" ON "CustomerAgreementAcceptance"("customerId", "agreementId");

-- CreateIndex
CREATE INDEX "Payment_customerId_status_createdAt_idx" ON "Payment"("customerId", "status", "createdAt");

-- CreateIndex
CREATE INDEX "Payment_organizationId_status_createdAt_idx" ON "Payment"("organizationId", "status", "createdAt");

-- CreateIndex
CREATE INDEX "Payment_buyForMeRequestId_idx" ON "Payment"("buyForMeRequestId");

-- CreateIndex
CREATE INDEX "Payment_shipForMeRequestId_idx" ON "Payment"("shipForMeRequestId");

-- CreateIndex
CREATE INDEX "PaymentMethodConfig_organizationId_serviceType_countryCode__idx" ON "PaymentMethodConfig"("organizationId", "serviceType", "countryCode", "isActive");

-- CreateIndex
CREATE INDEX "ReturnRequest_customerId_status_createdAt_idx" ON "ReturnRequest"("customerId", "status", "createdAt");

-- CreateIndex
CREATE INDEX "ReturnRequest_organizationId_status_createdAt_idx" ON "ReturnRequest"("organizationId", "status", "createdAt");

-- AddForeignKey
ALTER TABLE "BuyForMeRequest" ADD CONSTRAINT "BuyForMeRequest_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "Customer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BuyForMeRequest" ADD CONSTRAINT "BuyForMeRequest_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BuyForMeRequest" ADD CONSTRAINT "BuyForMeRequest_parcelId_fkey" FOREIGN KEY ("parcelId") REFERENCES "Parcel"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ShipForMeRequest" ADD CONSTRAINT "ShipForMeRequest_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "Customer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ShipForMeRequest" ADD CONSTRAINT "ShipForMeRequest_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ShipForMeRequest" ADD CONSTRAINT "ShipForMeRequest_parcelId_fkey" FOREIGN KEY ("parcelId") REFERENCES "Parcel"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "WarehouseAddress" ADD CONSTRAINT "WarehouseAddress_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CustomerAgreementAcceptance" ADD CONSTRAINT "CustomerAgreementAcceptance_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "Customer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CustomerAgreementAcceptance" ADD CONSTRAINT "CustomerAgreementAcceptance_agreementId_fkey" FOREIGN KEY ("agreementId") REFERENCES "CustomerAgreement"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Payment" ADD CONSTRAINT "Payment_buyForMeRequestId_fkey" FOREIGN KEY ("buyForMeRequestId") REFERENCES "BuyForMeRequest"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Payment" ADD CONSTRAINT "Payment_shipForMeRequestId_fkey" FOREIGN KEY ("shipForMeRequestId") REFERENCES "ShipForMeRequest"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Payment" ADD CONSTRAINT "Payment_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "Customer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReturnRequest" ADD CONSTRAINT "ReturnRequest_buyForMeRequestId_fkey" FOREIGN KEY ("buyForMeRequestId") REFERENCES "BuyForMeRequest"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReturnRequest" ADD CONSTRAINT "ReturnRequest_shipForMeRequestId_fkey" FOREIGN KEY ("shipForMeRequestId") REFERENCES "ShipForMeRequest"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReturnRequest" ADD CONSTRAINT "ReturnRequest_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "Customer"("id") ON DELETE CASCADE ON UPDATE CASCADE;
