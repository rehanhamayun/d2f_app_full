-- CreateTable
CREATE TABLE "ConnectTravellerDeclaration" (
    "id" TEXT NOT NULL,
    "assignmentId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "legalName" TEXT NOT NULL,
    "contentsHash" TEXT NOT NULL,
    "termsVersion" TEXT NOT NULL,
    "contents" TEXT NOT NULL,
    "checks" JSONB NOT NULL,
    "acknowledgment" TEXT NOT NULL,
    "audit" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ConnectTravellerDeclaration_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LabelPrintJob" (
    "id" TEXT NOT NULL,
    "organizationId" TEXT NOT NULL,
    "parcelId" TEXT NOT NULL,
    "actorId" TEXT NOT NULL,
    "clientJobId" TEXT NOT NULL,
    "printerName" TEXT NOT NULL,
    "printerAddress" TEXT,
    "labelHash" TEXT NOT NULL,
    "pages" INTEGER NOT NULL,
    "status" TEXT NOT NULL,
    "message" TEXT,
    "source" TEXT NOT NULL,
    "reason" TEXT,
    "deviceAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LabelPrintJob_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ConnectTravellerDeclaration_assignmentId_createdAt_idx" ON "ConnectTravellerDeclaration"("assignmentId", "createdAt");

-- CreateIndex
CREATE INDEX "LabelPrintJob_organizationId_parcelId_createdAt_idx" ON "LabelPrintJob"("organizationId", "parcelId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "LabelPrintJob_organizationId_actorId_clientJobId_key" ON "LabelPrintJob"("organizationId", "actorId", "clientJobId");

-- AddForeignKey
ALTER TABLE "ConnectTravellerDeclaration" ADD CONSTRAINT "ConnectTravellerDeclaration_assignmentId_fkey" FOREIGN KEY ("assignmentId") REFERENCES "ConnectAssignment"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
