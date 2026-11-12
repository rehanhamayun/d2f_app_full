-- AlterTable
ALTER TABLE "Notification" ADD COLUMN     "entityId" TEXT,
ADD COLUMN     "entityType" TEXT,
ADD COLUMN     "eventKey" TEXT,
ADD COLUMN     "pushQueuedAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "ConnectTrip" ADD COLUMN     "departureTimezone" TEXT,
ADD COLUMN     "destinationTimezone" TEXT;

ALTER TABLE "ConnectBooking" ADD COLUMN "preferredTimezone" TEXT;

-- CreateTable
CREATE TABLE "PushDevice" (
    "id" TEXT NOT NULL,
    "token" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "platform" TEXT NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PushDevice_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PushDelivery" (
    "id" TEXT NOT NULL,
    "notificationId" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "nextAttemptAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "leaseUntil" TIMESTAMP(3),
    "completedAt" TIMESTAMP(3),
    "lastError" TEXT,

    CONSTRAINT "PushDelivery_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "PushDevice_token_key" ON "PushDevice"("token");

-- CreateIndex
CREATE INDEX "PushDevice_userId_idx" ON "PushDevice"("userId");

-- CreateIndex
CREATE INDEX "PushDelivery_completedAt_nextAttemptAt_idx" ON "PushDelivery"("completedAt", "nextAttemptAt");

-- CreateIndex
CREATE UNIQUE INDEX "PushDelivery_notificationId_deviceId_key" ON "PushDelivery"("notificationId", "deviceId");

-- CreateIndex
CREATE INDEX "Notification_pushQueuedAt_createdAt_idx" ON "Notification"("pushQueuedAt", "createdAt");

-- AddForeignKey
ALTER TABLE "PushDevice" ADD CONSTRAINT "PushDevice_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PushDelivery" ADD CONSTRAINT "PushDelivery_notificationId_fkey" FOREIGN KEY ("notificationId") REFERENCES "Notification"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PushDelivery" ADD CONSTRAINT "PushDelivery_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "PushDevice"("id") ON DELETE CASCADE ON UPDATE CASCADE;


-- Existing inbox history should not suddenly push when credentials are enabled.
UPDATE "Notification" SET "pushQueuedAt" = CURRENT_TIMESTAMP;
CREATE UNIQUE INDEX "Notification_eventKey_key" ON "Notification"("eventKey");

-- All customer-visible operational events write their alerts atomically.
-- Triggers also cover bulk/container updates and retries, without networking
-- inside business transactions. Internal notes and payment evidence stay private.
CREATE FUNCTION d2f_alert(uid TEXT, kind TEXT, heading TEXT, message TEXT, entity TEXT, eid TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF uid IS NOT NULL THEN
    INSERT INTO "Notification" (id,"userId",type,title,body,"entityType","entityId","eventKey")
    SELECT gen_random_uuid()::text, uid, kind, heading, message, entity, eid, concat(txid_current(), ':', entity, ':', eid, ':', uid)
    WHERE EXISTS (SELECT 1 FROM "User" WHERE id = uid AND "isActive" = true)
    ON CONFLICT ("eventKey") DO UPDATE SET title=EXCLUDED.title, body=EXCLUDED.body;
  END IF;
END $$;

CREATE FUNCTION d2f_operation_alert() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE n JSONB := to_jsonb(NEW); o JSONB := '{}'; uid TEXT; org TEXT; eid TEXT; kind TEXT; heading TEXT; message TEXT; customer TEXT;
BEGIN
  IF TG_OP = 'UPDATE' THEN o := to_jsonb(OLD); END IF;
  eid := n->>'id'; org := n->>'organizationId';
  kind := upper(TG_TABLE_NAME) || '_UPDATE';
  heading := 'D2F update';
  IF TG_TABLE_NAME = 'Parcel' THEN
    IF TG_OP='INSERT' THEN RETURN NEW; END IF;
    IF (n->'pickupDriverId',n->'deliveryDriverId') IS DISTINCT FROM (o->'pickupDriverId',o->'deliveryDriverId') THEN
      IF n->'pickupDriverId' IS DISTINCT FROM o->'pickupDriverId' THEN PERFORM d2f_alert(n->>'pickupDriverId', 'DRIVER_ASSIGNMENT', 'Pickup assignment', 'D2F updated your pickup assignment. Check your assigned shipments.', 'Parcel', eid); END IF;
      IF n->'deliveryDriverId' IS DISTINCT FROM o->'deliveryDriverId' THEN PERFORM d2f_alert(n->>'deliveryDriverId', 'DRIVER_ASSIGNMENT', 'Delivery assignment', 'D2F updated your delivery assignment. Check your assigned shipments.', 'Parcel', eid); END IF;
    END IF;
    IF (n->'origin',n->'destination',n->'recipientName',n->'recipientPhone',n->'recipientAddress',n->'awbNumber',n->'airline',n->'flightNumber',n->'pickupScheduledAt',n->'deliveryMode') IS NOT DISTINCT FROM (o->'origin',o->'destination',o->'recipientName',o->'recipientPhone',o->'recipientAddress',o->'awbNumber',o->'airline',o->'flightNumber',o->'pickupScheduledAt',o->'deliveryMode') THEN RETURN NEW; END IF;
    SELECT "userId" INTO uid FROM "Customer" WHERE id=n->>'customerId';
    PERFORM d2f_alert(uid, 'SHIPMENT_UPDATE', 'Shipment details updated', 'D2F updated your shipment details. Open the shipment to review the latest information.', 'Parcel', eid);
    RETURN NEW;
  ELSIF TG_TABLE_NAME = 'TrackingEvent' THEN
    SELECT c."userId", p."organizationId" INTO uid, org FROM "Parcel" p JOIN "Customer" c ON c.id=p."customerId" WHERE p.id=n->>'parcelId';
    eid := n->>'parcelId'; heading := 'Shipment update'; kind := 'SHIPMENT_UPDATE';
    message := coalesce(n->>'note', replace(n->>'status', '_', ' '));
    PERFORM d2f_alert(uid, kind, heading, message, 'Parcel', eid);
    RETURN NEW;
  ELSIF TG_TABLE_NAME = 'ServiceOrder' THEN
    IF TG_OP = 'UPDATE' AND (n->'status', n->'amountMinor', n->'paymentStatus', n->'shippingTrackingNumber', n->'deliveryService', n->'shippingLabelUrl', n->'trackingRef', n->'shippingCarrier', n->'parcelId') IS NOT DISTINCT FROM (o->'status', o->'amountMinor', o->'paymentStatus', o->'shippingTrackingNumber', o->'deliveryService', o->'shippingLabelUrl', o->'trackingRef', o->'shippingCarrier', o->'parcelId') THEN RETURN NEW; END IF;
    heading := CASE WHEN n->>'kind'='BUY_FOR_ME' THEN 'Buy for ME' ELSE 'Marketplace order' END;
    message := (n->>'title') || ' · ' || replace(n->>'status', '_', ' ');
    IF n->>'status'='QUOTED' THEN message := message || '. Review your quote in the app.'; END IF;
    kind := CASE WHEN n->>'kind'='BUY_FOR_ME' THEN 'BUY_FOR_ME_' ELSE 'ORDER_' END || (n->>'status');
    customer := n->>'customerId';
    IF n->>'productId' IS NOT NULL THEN
      PERFORM d2f_alert(s."userId", kind, heading, message, TG_TABLE_NAME, eid) FROM "Product" p JOIN "SellerProfile" s ON s.id=p."sellerId" WHERE p.id=n->>'productId';
    END IF;
  ELSIF TG_TABLE_NAME = 'ServiceOrderUpdate' THEN
    -- Status/delivery changes already generate an order alert. Message-only
    -- updates still need their own notification, including image-only updates.
    IF n->>'status' IS NOT NULL THEN RETURN NEW; END IF;
    SELECT c."userId" INTO uid FROM "ServiceOrder" s JOIN "Customer" c ON c.id=s."customerId" WHERE s.id=n->>'serviceOrderId';
    PERFORM d2f_alert(uid, 'BUY_FOR_ME_UPDATE', 'New Buy for ME update', n->>'message', 'ServiceOrder', n->>'serviceOrderId');
    RETURN NEW;
  ELSIF TG_TABLE_NAME = 'ConnectTrip' THEN
    IF TG_OP = 'UPDATE' AND (n->'status',n->'departureAt',n->'departureTimezone',n->'destinationTimezone',n->'receivingLocationId') IS NOT DISTINCT FROM (o->'status',o->'departureAt',o->'departureTimezone',o->'destinationTimezone',o->'receivingLocationId') THEN RETURN NEW; END IF;
    uid := n->>'travellerId'; heading := 'D2F Connect trip';
    message := (n->>'origin') || ' → ' || (n->>'destination') || ' · ' || replace(n->>'status','_',' ');
  ELSIF TG_TABLE_NAME = 'ConnectAssignment' THEN
    IF TG_OP='UPDATE' AND n->'status' IS NOT DISTINCT FROM o->'status' THEN RETURN NEW; END IF;
    SELECT t."travellerId", t."organizationId" INTO uid, org FROM "ConnectTrip" t WHERE t.id=n->>'tripId';
    heading := 'Connect parcel assignment'; message := 'Your parcel assignment is now ' || replace(n->>'status','_',' ') || '. Review it in D2F Connect.';
  ELSIF TG_TABLE_NAME = 'ServiceOrderPaymentSubmission' OR TG_TABLE_NAME = 'ConnectPaymentSubmission' THEN
    IF TG_OP='UPDATE' AND n->'status' IS NOT DISTINCT FROM o->'status' THEN RETURN NEW; END IF;
    IF TG_TABLE_NAME='ServiceOrderPaymentSubmission' THEN
      SELECT s."organizationId" INTO org FROM "ServiceOrder" s WHERE s.id=n->>'serviceOrderId';
    ELSE
      SELECT b."organizationId" INTO org FROM "ConnectBooking" b WHERE b.id=n->>'bookingId';
    END IF;
    uid := n->>'userId'; heading := 'Payment evidence';
    message := CASE WHEN TG_OP='INSERT' THEN 'Your payment proof was received and is awaiting review.' ELSE 'Your payment proof is ' || lower(n->>'status') || '. ' || coalesce(n->>'reviewNote','') END;
  ELSIF TG_TABLE_NAME IN ('BuyForMeRequest','ShipForMeRequest','Payment','ReturnRequest') THEN
    IF TG_OP='UPDATE' AND (n->'status',n->'paymentStatus',n->'totalQuoteMinor',n->'shippingCostMinor',n->'adminDecision') IS NOT DISTINCT FROM (o->'status',o->'paymentStatus',o->'totalQuoteMinor',o->'shippingCostMinor',o->'adminDecision') THEN RETURN NEW; END IF;
    customer := n->>'customerId'; heading := CASE TG_TABLE_NAME WHEN 'ShipForMeRequest' THEN 'Ship for ME' WHEN 'BuyForMeRequest' THEN 'Buy for ME' WHEN 'ReturnRequest' THEN 'Return request' ELSE 'Payment' END;
    message := heading || ' · ' || replace(coalesce(n->>'status','Updated'),'_',' ') || '. Open the app for details.';
  ELSIF TG_TABLE_NAME IN ('SellerProfile','Product') THEN
    IF TG_OP='UPDATE' AND n->'status' IS NOT DISTINCT FROM o->'status' THEN RETURN NEW; END IF;
    IF TG_TABLE_NAME='SellerProfile' THEN uid := n->>'userId'; ELSE
      SELECT s."userId", s."organizationId" INTO uid, org FROM "SellerProfile" s WHERE s.id=n->>'sellerId';
    END IF;
    heading := CASE TG_TABLE_NAME WHEN 'Product' THEN 'Marketplace product' ELSE 'Seller account' END;
    message := heading || ' · ' || replace(coalesce(n->>'status','Submitted'),'_',' ');
  END IF;
  IF customer IS NOT NULL THEN SELECT "userId" INTO uid FROM "Customer" WHERE id=customer; END IF;
  PERFORM d2f_alert(uid, kind, heading, message, TG_TABLE_NAME, eid);
  -- New requests, evidence, and customer decisions keep the owning admin team informed.
  IF org IS NOT NULL AND (TG_OP='INSERT' OR (n->>'status' IN ('ACCEPTED','CANCELLED','SUBMITTED') AND n->'status' IS DISTINCT FROM o->'status')) THEN
    PERFORM d2f_alert(u.id, kind, heading, message, TG_TABLE_NAME, eid) FROM "User" u WHERE u."organizationId"=org AND u.role='ADMIN' AND u.id IS DISTINCT FROM uid;
  END IF;
  RETURN NEW;
END $$;

DO $$ DECLARE tbl TEXT; BEGIN
  FOREACH tbl IN ARRAY ARRAY['Parcel','TrackingEvent','ServiceOrder','ServiceOrderUpdate','ConnectTrip','ConnectAssignment','ServiceOrderPaymentSubmission','ConnectPaymentSubmission','BuyForMeRequest','ShipForMeRequest','Payment','ReturnRequest','SellerProfile','Product'] LOOP
    EXECUTE format('CREATE TRIGGER d2f_operation_alert AFTER INSERT OR UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION d2f_operation_alert()', tbl);
  END LOOP;
END $$;
