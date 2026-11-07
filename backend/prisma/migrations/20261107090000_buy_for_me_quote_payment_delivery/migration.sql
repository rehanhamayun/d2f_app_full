ALTER TABLE "ServiceOrder"
ADD COLUMN "deliveryPostalCode" TEXT,
ADD COLUMN "deliveryStateProvince" TEXT,
ADD COLUMN "productCostMinor" INTEGER,
ADD COLUMN "shippingCostMinor" INTEGER,
ADD COLUMN "paymentStatus" TEXT NOT NULL DEFAULT 'NOT_SUBMITTED',
ADD COLUMN "paymentTransactionId" TEXT,
ADD COLUMN "deliveryService" TEXT,
ADD COLUMN "shippingCarrier" TEXT,
ADD COLUMN "shippingTrackingNumber" TEXT,
ADD COLUMN "shippingLabelUrl" TEXT;

CREATE TABLE "ServiceOrderPaymentSubmission" (
    "id" TEXT NOT NULL,
    "serviceOrderId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "method" TEXT NOT NULL,
    "transactionId" TEXT NOT NULL,
    "fileName" TEXT NOT NULL,
    "contentType" TEXT NOT NULL,
    "bytes" BYTEA NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "reviewNote" TEXT,
    "reviewedById" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ServiceOrderPaymentSubmission_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "ServiceOrderPaymentSubmission_serviceOrderId_fkey"
      FOREIGN KEY ("serviceOrderId") REFERENCES "ServiceOrder"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE INDEX "ServiceOrderPaymentSubmission_serviceOrderId_createdAt_idx"
  ON "ServiceOrderPaymentSubmission"("serviceOrderId", "createdAt");

CREATE TABLE "ServiceOrderUpdate" (
    "id" TEXT NOT NULL,
    "serviceOrderId" TEXT NOT NULL,
    "actorId" TEXT NOT NULL,
    "status" TEXT,
    "message" TEXT NOT NULL,
    "deliveryService" TEXT,
    "shippingCarrier" TEXT,
    "shippingTrackingNumber" TEXT,
    "shippingLabelUrl" TEXT,
    "fileName" TEXT,
    "contentType" TEXT,
    "bytes" BYTEA,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ServiceOrderUpdate_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "ServiceOrderUpdate_serviceOrderId_fkey"
      FOREIGN KEY ("serviceOrderId") REFERENCES "ServiceOrder"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE INDEX "ServiceOrderUpdate_serviceOrderId_createdAt_idx"
  ON "ServiceOrderUpdate"("serviceOrderId", "createdAt");
