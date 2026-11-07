ALTER TABLE "ServiceOrderPaymentSubmission"
DROP CONSTRAINT "ServiceOrderPaymentSubmission_serviceOrderId_fkey",
ADD CONSTRAINT "ServiceOrderPaymentSubmission_serviceOrderId_fkey"
  FOREIGN KEY ("serviceOrderId") REFERENCES "ServiceOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "ServiceOrderUpdate"
DROP CONSTRAINT "ServiceOrderUpdate_serviceOrderId_fkey",
ADD CONSTRAINT "ServiceOrderUpdate_serviceOrderId_fkey"
  FOREIGN KEY ("serviceOrderId") REFERENCES "ServiceOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;
