ALTER TABLE "Parcel" ADD COLUMN "orderType" TEXT, ADD COLUMN "onwardDispatchedAt" TIMESTAMP(3);
ALTER TABLE "Container" ADD COLUMN "onwardCountries" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
ALTER TABLE "ServiceOrder" ADD COLUMN "pickupFeeMinor" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "handlingFeeMinor" INTEGER NOT NULL DEFAULT 0, ADD COLUMN "deliveryMethod" TEXT,
  ADD COLUMN "deliveryEvidence" TEXT, ADD COLUMN "deliveryConfirmedAt" TIMESTAMP(3),
  ADD COLUMN "deliveryConfirmedById" TEXT;
ALTER TABLE "ConnectTrip" ADD COLUMN "arrivalAt" TIMESTAMP(3), ADD COLUMN "airline" TEXT,
  ADD COLUMN "verificationChecks" JSONB, ALTER COLUMN "verificationReference" DROP NOT NULL;
ALTER TABLE "Organization" ADD COLUMN "retailerLinks" JSONB;
CREATE TABLE "ConnectTripVerificationDocument" (
  "tripId" TEXT NOT NULL,
  "kind" TEXT NOT NULL,
  "contentType" TEXT NOT NULL,
  "bytes" BYTEA NOT NULL,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  PRIMARY KEY ("tripId", "kind"),
  FOREIGN KEY ("tripId") REFERENCES "ConnectTrip"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
ALTER TABLE "ServiceOrder" ADD COLUMN "shipmentEvidence" TEXT,
  ADD COLUMN "marketplacePaymentMethod" TEXT, ADD COLUMN "marketplacePaymentVerifiedAt" TIMESTAMP(3),
  ADD COLUMN "marketplacePaymentVerifiedById" TEXT, ADD COLUMN "marketplacePaymentNote" TEXT,
  ADD COLUMN "marketplaceInvoice" JSONB;
ALTER TABLE "SellerProfile" ADD COLUMN "storefrontOrder" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "whatsappNumber" TEXT, ADD COLUMN "localDeliveryEnabled" BOOLEAN NOT NULL DEFAULT FALSE;
CREATE TABLE "MarketplaceOrderIssue" (
  "id" TEXT PRIMARY KEY,
  "serviceOrderId" TEXT NOT NULL REFERENCES "ServiceOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "type" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'OPEN',
  "reason" TEXT NOT NULL,
  "evidence" TEXT,
  "amountMinor" INTEGER,
  "openedById" TEXT NOT NULL,
  "resolvedById" TEXT,
  "resolution" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "resolvedAt" TIMESTAMP(3)
);
CREATE INDEX "MarketplaceOrderIssue_serviceOrderId_createdAt_idx" ON "MarketplaceOrderIssue"("serviceOrderId", "createdAt");
CREATE UNIQUE INDEX "MarketplaceOrderIssue_one_open_type" ON "MarketplaceOrderIssue"("serviceOrderId", "type") WHERE "status" = 'OPEN';
