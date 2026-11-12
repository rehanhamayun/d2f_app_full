ALTER TABLE "ServiceOrder" ADD COLUMN "clientRequestId" TEXT;
CREATE UNIQUE INDEX "ServiceOrder_organizationId_clientRequestId_key" ON "ServiceOrder"("organizationId", "clientRequestId");
