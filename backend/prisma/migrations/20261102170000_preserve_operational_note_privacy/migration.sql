-- Retain original staff notes privately; publish factual status copy only.
UPDATE "TrackingEvent" e SET "originalNote"=COALESCE(e."originalNote",e.note), "internalNote"=COALESCE(e."internalNote",e.note), note=CASE e.status
WHEN 'REQUESTED' THEN 'Shipment request submitted; awaiting physical collection or drop-off.'
WHEN 'RECEIVED' THEN 'Parcel received at the origin warehouse.'
WHEN 'PROCESSING' THEN 'Parcel is being processed at the warehouse.'
WHEN 'READY_FOR_LOADING' THEN 'Parcel is ready for loading; shipment has not departed.'
WHEN 'LOADED_IN_CONTAINER' THEN 'Parcel loaded into its assigned container; awaiting departure.'
WHEN 'IN_TRANSIT' THEN 'Shipment departure confirmed; in transit.'
WHEN 'ARRIVED_PORT' THEN 'Shipment arrived at the destination port; awaiting customs clearance.'
WHEN 'CUSTOMS_CLEARANCE' THEN 'Shipment is undergoing customs clearance.'
WHEN 'CUSTOMS_CLEARED' THEN 'Customs release confirmed; awaiting destination warehouse receipt.'
WHEN 'RECEIVED_DESTINATION' THEN 'Parcel received at the destination warehouse.'
WHEN 'ARRIVED_LOME' THEN 'Parcel received at Lomé warehouse.'
WHEN 'ARRIVED_DESTINATION' THEN 'Parcel received at the destination facility.'
WHEN 'READY_FOR_PICKUP' THEN 'Parcel ready for pickup or delivery scheduling.'
WHEN 'OUT_FOR_DELIVERY' THEN 'Parcel is with the assigned delivery driver.'
WHEN 'RELEASED' THEN 'Parcel released to the authorized recipient.'
WHEN 'DELIVERED' THEN 'Delivery confirmed with recipient handover evidence.'
ELSE 'D2F recorded an operational update.' END
FROM "User" u WHERE e."actorId"=u.id AND u.role IN ('STAFF','ADMIN') AND e."internalNote" IS NULL AND e.note IS NOT NULL;

-- Clarify only loading already physically recorded by a container scan.
WITH clarified AS (
 UPDATE "Parcel" p SET status='LOADED_IN_CONTAINER', "updatedAt"=CURRENT_TIMESTAMP FROM "Container" c
 WHERE p."containerId"=c.id AND c.method='SEA' AND c.status='LOADING'
 AND p.status IN ('RECEIVED','PROCESSING') AND p."warehouseReceivedAt" IS NOT NULL
 AND EXISTS(SELECT 1 FROM "TrackingEvent" e WHERE e."parcelId"=p.id AND (e.note LIKE 'Loaded into container %' OR e."internalNote" LIKE 'Loaded into container %'))
 RETURNING p.id,p."locationId",p."trackingId"
), events AS (
 INSERT INTO "TrackingEvent" (id,"parcelId",status,note,"internalNote","originalNote","facilityId","createdAt")
 SELECT gen_random_uuid()::text,id,'LOADED_IN_CONTAINER','Parcel loaded into its assigned container; awaiting departure.','Tracking stage clarified from previously recorded physical container loading; no departure is implied.','Tracking stage clarified from previously recorded physical container loading; no departure is implied.',"locationId",CURRENT_TIMESTAMP FROM clarified RETURNING "parcelId"
)
INSERT INTO "AuditLog" (id,action,entity,"entityId",detail,"createdAt") SELECT gen_random_uuid()::text,'LEGACY_LOADING_STAGE_CLARIFIED','Parcel',"parcelId",'System migration: existing confirmed loading mapped to explicit Loaded into Container stage. Original history preserved.',CURRENT_TIMESTAMP FROM events;
