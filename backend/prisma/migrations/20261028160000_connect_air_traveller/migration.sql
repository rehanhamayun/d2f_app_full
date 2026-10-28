-- AlterTable
ALTER TABLE "Location" ADD COLUMN     "address" TEXT,
ADD COLUMN     "connectReceiving" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE "Parcel" ADD COLUMN     "airline" TEXT,
ADD COLUMN     "awbNumber" TEXT,
ADD COLUMN     "customsDocuments" TEXT,
ADD COLUMN     "flightNumber" TEXT,
ADD COLUMN     "serviceType" TEXT NOT NULL DEFAULT 'SEA',
ADD COLUMN     "volumetricWeightKg" DOUBLE PRECISION;

-- CreateTable
CREATE TABLE "ConnectTrip" (
    "id" TEXT NOT NULL,
    "organizationId" TEXT NOT NULL,
    "travellerId" TEXT NOT NULL,
    "origin" TEXT NOT NULL,
    "destination" TEXT NOT NULL,
    "departureAt" TIMESTAMP(3) NOT NULL,
    "flightNumber" TEXT NOT NULL,
    "capacityKg" DOUBLE PRECISION NOT NULL,
    "categories" TEXT[],
    "verificationReference" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING_REVIEW',
    "reviewNote" TEXT,
    "receivingLocationId" TEXT,
    "compensationMinor" INTEGER NOT NULL DEFAULT 0,
    "expensesMinor" INTEGER NOT NULL DEFAULT 0,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ConnectTrip_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ConnectRate" (
    "id" TEXT NOT NULL,
    "organizationId" TEXT NOT NULL,
    "origin" TEXT NOT NULL,
    "destination" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "unit" TEXT NOT NULL,
    "amountMinor" INTEGER NOT NULL,
    "maxWeightKg" DOUBLE PRECISION,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ConnectRate_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ConnectBooking" (
    "id" TEXT NOT NULL,
    "organizationId" TEXT NOT NULL,
    "parcelId" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "quantity" INTEGER NOT NULL,
    "declaredValueMinor" INTEGER NOT NULL,
    "preferredDate" TIMESTAMP(3) NOT NULL,
    "requestedTripId" TEXT,
    "verifiedWeightKg" DOUBLE PRECISION,
    "contentsVerifiedAt" TIMESTAMP(3),
    "contentsVerificationNote" TEXT,
    "internationalFeeMinor" INTEGER,
    "domesticCostMinor" INTEGER,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "pricingSnapshot" JSONB,
    "quoteAcceptedAt" TIMESTAMP(3),
    "handoverMode" TEXT NOT NULL,
    "senderCity" TEXT NOT NULL,
    "senderAddress" TEXT,
    "deliveryPreference" TEXT NOT NULL DEFAULT 'D2F_PICKUP',
    "domesticCarrier" TEXT,
    "domesticTrackingNumber" TEXT,
    "domesticLabelUrl" TEXT,
    "domesticStatus" TEXT NOT NULL DEFAULT 'NOT_REQUIRED',
    "receivingLocationId" TEXT,
    "originReceivedAt" TIMESTAMP(3),
    "handoverCodeHash" TEXT,
    "handoverCodeExpiresAt" TIMESTAMP(3),
    "handoverAttempts" INTEGER NOT NULL DEFAULT 0,
    "collectedAt" TIMESTAMP(3),
    "destinationReceivedAt" TIMESTAMP(3),
    "deliveredAt" TIMESTAMP(3),
    "deliveryEvidence" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ConnectBooking_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ConnectAssignment" (
    "id" TEXT NOT NULL,
    "bookingId" TEXT NOT NULL,
    "tripId" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PROPOSED',
    "responseNote" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "acceptedAt" TIMESTAMP(3),
    "confirmedAt" TIMESTAMP(3),

    CONSTRAINT "ConnectAssignment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ConnectPayment" (
    "id" TEXT NOT NULL,
    "organizationId" TEXT NOT NULL,
    "bookingId" TEXT NOT NULL,
    "reference" TEXT NOT NULL,
    "amountMinor" INTEGER NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "recordedById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ConnectPayment_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ConnectTrip_organizationId_status_departureAt_idx" ON "ConnectTrip"("organizationId", "status", "departureAt");

-- CreateIndex
CREATE UNIQUE INDEX "ConnectRate_organizationId_origin_destination_category_key" ON "ConnectRate"("organizationId", "origin", "destination", "category");

-- CreateIndex
CREATE UNIQUE INDEX "ConnectBooking_parcelId_key" ON "ConnectBooking"("parcelId");

-- CreateIndex
CREATE INDEX "ConnectBooking_organizationId_createdAt_idx" ON "ConnectBooking"("organizationId", "createdAt");

-- CreateIndex
CREATE INDEX "ConnectAssignment_tripId_status_idx" ON "ConnectAssignment"("tripId", "status");

-- CreateIndex
CREATE INDEX "ConnectAssignment_bookingId_status_idx" ON "ConnectAssignment"("bookingId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "ConnectPayment_bookingId_key" ON "ConnectPayment"("bookingId");

-- CreateIndex
CREATE UNIQUE INDEX "ConnectPayment_organizationId_reference_key" ON "ConnectPayment"("organizationId", "reference");

-- AddForeignKey
ALTER TABLE "ConnectTrip" ADD CONSTRAINT "ConnectTrip_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConnectTrip" ADD CONSTRAINT "ConnectTrip_travellerId_fkey" FOREIGN KEY ("travellerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConnectTrip" ADD CONSTRAINT "ConnectTrip_receivingLocationId_fkey" FOREIGN KEY ("receivingLocationId") REFERENCES "Location"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConnectRate" ADD CONSTRAINT "ConnectRate_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConnectBooking" ADD CONSTRAINT "ConnectBooking_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConnectBooking" ADD CONSTRAINT "ConnectBooking_parcelId_fkey" FOREIGN KEY ("parcelId") REFERENCES "Parcel"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConnectBooking" ADD CONSTRAINT "ConnectBooking_requestedTripId_fkey" FOREIGN KEY ("requestedTripId") REFERENCES "ConnectTrip"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConnectBooking" ADD CONSTRAINT "ConnectBooking_receivingLocationId_fkey" FOREIGN KEY ("receivingLocationId") REFERENCES "Location"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConnectAssignment" ADD CONSTRAINT "ConnectAssignment_bookingId_fkey" FOREIGN KEY ("bookingId") REFERENCES "ConnectBooking"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConnectAssignment" ADD CONSTRAINT "ConnectAssignment_tripId_fkey" FOREIGN KEY ("tripId") REFERENCES "ConnectTrip"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConnectPayment" ADD CONSTRAINT "ConnectPayment_bookingId_fkey" FOREIGN KEY ("bookingId") REFERENCES "ConnectBooking"("id") ON DELETE RESTRICT ON UPDATE CASCADE;


-- Preserve the meaning of existing conventional shipping services.
UPDATE "Parcel" SET "serviceType" = CASE WHEN "method" = 'AIR' THEN 'AIR_CARGO' ELSE "method" END;
ALTER TABLE "Parcel" ADD CONSTRAINT "Parcel_service_type_check" CHECK ("serviceType" IN ('AIR_CARGO', 'AIR_TRAVELLER', 'SEA', 'ROAD'));
ALTER TABLE "Parcel" ADD CONSTRAINT "Parcel_awb_cargo_only" CHECK ("serviceType" = 'AIR_CARGO' OR ("awbNumber" IS NULL AND "airline" IS NULL AND "flightNumber" IS NULL AND "volumetricWeightKg" IS NULL AND "customsDocuments" IS NULL));
ALTER TABLE "ConnectTrip" ADD CONSTRAINT "ConnectTrip_capacity_check" CHECK ("capacityKg" > 0 AND "compensationMinor" >= 0 AND "expensesMinor" >= 0);
ALTER TABLE "ConnectBooking" ADD CONSTRAINT "ConnectBooking_amounts_check" CHECK ("quantity" > 0 AND "declaredValueMinor" >= 0 AND ("internationalFeeMinor" IS NULL OR "internationalFeeMinor" >= 0) AND ("domesticCostMinor" IS NULL OR "domesticCostMinor" >= 0));

ALTER TABLE "ConnectBooking" ADD COLUMN "paymentInstructions" TEXT;
