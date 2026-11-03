-- AlterTable
ALTER TABLE "ConnectBooking" ADD COLUMN     "complianceReviewedById" TEXT,
ADD COLUMN     "paymentInstructionsVersion" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "reviewedDeclarationId" TEXT;

-- AlterTable
ALTER TABLE "TrackingEvent" ADD COLUMN     "facilityId" TEXT,
ADD COLUMN     "internalNote" TEXT,
ADD COLUMN     "originalNote" TEXT,
ADD COLUMN     "templateId" TEXT;

-- CreateTable
CREATE TABLE "ConnectDeclaration" (
    "id" TEXT NOT NULL,
    "bookingId" TEXT NOT NULL,
    "customerId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "legalName" TEXT NOT NULL,
    "contents" TEXT NOT NULL,
    "contentsHash" TEXT NOT NULL,
    "termsVersion" TEXT NOT NULL,
    "acknowledgment" TEXT NOT NULL,
    "checks" JSONB NOT NULL,
    "guidance" JSONB NOT NULL,
    "audit" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ConnectDeclaration_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ConnectPaymentSubmission" (
    "id" TEXT NOT NULL,
    "bookingId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "method" TEXT NOT NULL,
    "transactionId" TEXT,
    "instructionsVersion" INTEGER NOT NULL,
    "instructionsSnapshot" TEXT NOT NULL,
    "fileName" TEXT,
    "contentType" TEXT,
    "bytes" BYTEA,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "reviewNote" TEXT,
    "reviewedById" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ConnectPaymentSubmission_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "OperationalNoteTemplate" (
    "id" TEXT NOT NULL,
    "organizationId" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "serviceType" TEXT NOT NULL DEFAULT 'ALL',
    "message" TEXT NOT NULL,
    "customerMessage" TEXT NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "position" INTEGER NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OperationalNoteTemplate_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ConnectDeclaration_bookingId_createdAt_idx" ON "ConnectDeclaration"("bookingId", "createdAt");

-- CreateIndex
CREATE INDEX "ConnectPaymentSubmission_bookingId_createdAt_idx" ON "ConnectPaymentSubmission"("bookingId", "createdAt");

-- CreateIndex
CREATE INDEX "OperationalNoteTemplate_organizationId_status_isActive_idx" ON "OperationalNoteTemplate"("organizationId", "status", "isActive");

-- AddForeignKey
ALTER TABLE "ConnectDeclaration" ADD CONSTRAINT "ConnectDeclaration_bookingId_fkey" FOREIGN KEY ("bookingId") REFERENCES "ConnectBooking"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConnectPaymentSubmission" ADD CONSTRAINT "ConnectPaymentSubmission_bookingId_fkey" FOREIGN KEY ("bookingId") REFERENCES "ConnectBooking"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
