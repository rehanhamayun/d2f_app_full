BEGIN;

CREATE TABLE "TrackingPrefixReservation" (
  "prefix" TEXT NOT NULL PRIMARY KEY,
  "organizationId" TEXT NOT NULL UNIQUE,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "TrackingPrefixReservation_format_check"
    CHECK ("prefix" ~ '^[A-Z0-9]{3,5}$')
);

-- Deliberately no foreign keys: deleting a business record cannot free its ID.
CREATE TABLE "TrackingNumberReservation" (
  "trackingId" TEXT NOT NULL PRIMARY KEY,
  "parcelId" TEXT NOT NULL UNIQUE,
  "organizationId" TEXT NOT NULL,
  "trackingSequence" BIGINT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX "TrackingNumberReservation_organizationId_trackingSequence_key"
  ON "TrackingNumberReservation"("organizationId", "trackingSequence");

INSERT INTO "TrackingPrefixReservation" ("prefix", "organizationId", "createdAt")
SELECT "trackingPrefix", "id", "createdAt" FROM "Organization";

-- Preserve any numeric-format identities created before the new allocator.
UPDATE "Parcel" AS p
SET "trackingSequence" = substring(p."trackingId" FROM length(o."trackingPrefix") + 1)::BIGINT
FROM "Organization" AS o
WHERE p."organizationId" = o."id" AND p."trackingSequence" IS NULL
  AND p."trackingId" ~ ('^' || o."trackingPrefix" || '([0-9]{12}|[0-9]{15})$');

UPDATE "Organization" AS o
SET "trackingCounter" = GREATEST(o."trackingCounter", COALESCE((
  SELECT MAX(p."trackingSequence") + 1 FROM "Parcel" AS p
  WHERE p."organizationId" = o."id"
), 1));

INSERT INTO "TrackingNumberReservation"
  ("trackingId", "parcelId", "organizationId", "trackingSequence", "createdAt")
SELECT "trackingId", "id", "organizationId", "trackingSequence", "createdAt"
FROM "Parcel";

CREATE FUNCTION keep_tracking_reservations_permanent()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'Tracking reservations are permanent';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER "TrackingPrefixReservation_permanent"
BEFORE UPDATE OR DELETE ON "TrackingPrefixReservation"
FOR EACH ROW EXECUTE FUNCTION keep_tracking_reservations_permanent();
CREATE TRIGGER "TrackingNumberReservation_permanent"
BEFORE UPDATE OR DELETE ON "TrackingNumberReservation"
FOR EACH ROW EXECUTE FUNCTION keep_tracking_reservations_permanent();

CREATE FUNCTION reserve_organization_tracking_prefix()
RETURNS TRIGGER AS $$
BEGIN
  NEW."trackingPrefix" := upper(btrim(NEW."trackingPrefix"));
  -- A native upsert of an existing organization must remain idempotent.
  IF EXISTS (SELECT 1 FROM "Organization"
    WHERE "id" = NEW."id" AND "trackingPrefix" = NEW."trackingPrefix") THEN
    RETURN NEW;
  END IF;
  INSERT INTO "TrackingPrefixReservation" ("prefix", "organizationId")
  VALUES (NEW."trackingPrefix", NEW."id");
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER "Organization_reserve_tracking_prefix"
BEFORE INSERT ON "Organization"
FOR EACH ROW EXECUTE FUNCTION reserve_organization_tracking_prefix();

ALTER TABLE "Organization" ADD CONSTRAINT "Organization_trackingCounter_positive"
CHECK ("trackingCounter" >= 1);

CREATE FUNCTION protect_organization_tracking_counter()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW."id" IS DISTINCT FROM OLD."id" THEN
    RAISE EXCEPTION 'Organization identities are permanent';
  END IF;
  IF NEW."trackingCounter" < OLD."trackingCounter" THEN
    RAISE EXCEPTION 'Tracking counters cannot move backwards';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER "Organization_protect_tracking_counter"
BEFORE UPDATE ON "Organization"
FOR EACH ROW EXECUTE FUNCTION protect_organization_tracking_counter();

CREATE FUNCTION reserve_parcel_tracking_identity()
RETURNS TRIGGER AS $$
DECLARE
  prefix TEXT;
BEGIN
  IF NEW."trackingSequence" IS NOT NULL THEN
    SELECT "trackingPrefix" INTO prefix FROM "Organization"
    WHERE "id" = NEW."organizationId";
    IF NEW."trackingSequence" < 1 OR NEW."trackingSequence" > 999999999999
      OR NEW."trackingId" IS DISTINCT FROM
        prefix || lpad(NEW."trackingSequence"::TEXT, 12, '0') THEN
      RAISE EXCEPTION 'Tracking number does not match its organization and sequence';
    END IF;
  END IF;
  INSERT INTO "TrackingNumberReservation"
    ("trackingId", "parcelId", "organizationId", "trackingSequence")
  VALUES (NEW."trackingId", NEW."id", NEW."organizationId", NEW."trackingSequence");
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER "Parcel_reserve_tracking_identity"
BEFORE INSERT ON "Parcel"
FOR EACH ROW EXECUTE FUNCTION reserve_parcel_tracking_identity();

CREATE FUNCTION protect_parcel_tracking_identity()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW."id" IS DISTINCT FROM OLD."id"
    OR NEW."trackingId" IS DISTINCT FROM OLD."trackingId"
    OR NEW."organizationId" IS DISTINCT FROM OLD."organizationId"
    OR NEW."trackingSequence" IS DISTINCT FROM OLD."trackingSequence" THEN
    RAISE EXCEPTION 'Parcel tracking identities are permanent';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER "Parcel_protect_tracking_identity"
BEFORE UPDATE ON "Parcel"
FOR EACH ROW EXECUTE FUNCTION protect_parcel_tracking_identity();

-- Enforce UUID-shaped identifiers on new rows without rewriting legacy rows.
ALTER TABLE "Parcel" ADD CONSTRAINT "Parcel_uuid_format_check"
CHECK ("id" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') NOT VALID;

DROP INDEX "Parcel_clientRequestId_key";
CREATE UNIQUE INDEX "Parcel_organizationId_clientRequestId_key"
ON "Parcel"("organizationId", "clientRequestId");

COMMIT;
