ALTER TABLE "Organization"
ADD COLUMN "trackingPrefix" TEXT,
ADD COLUMN "trackingCounter" BIGINT NOT NULL DEFAULT 1;

DO $$
DECLARE
  organization_row RECORD;
  candidate TEXT;
  attempt INTEGER;
BEGIN
  FOR organization_row IN
    SELECT "id" FROM "Organization" ORDER BY "id"
  LOOP
    IF organization_row."id" = 'org-d2f' THEN
      UPDATE "Organization" SET "trackingPrefix" = 'D2F'
      WHERE "id" = organization_row."id";
      CONTINUE;
    END IF;

    attempt := 0;
    LOOP
      candidate := translate(
        substr(md5(organization_row."id" || ':' || attempt::TEXT), 1, 5),
        '0123456789abcdef',
        'ABCDEFGHIJKLMNOP'
      );
      EXIT WHEN NOT EXISTS (
        SELECT 1 FROM "Organization" WHERE "trackingPrefix" = candidate
      );
      attempt := attempt + 1;
    END LOOP;

    UPDATE "Organization" SET "trackingPrefix" = candidate
    WHERE "id" = organization_row."id";
  END LOOP;
END $$;

ALTER TABLE "Organization"
ALTER COLUMN "trackingPrefix" SET NOT NULL,
ADD CONSTRAINT "Organization_trackingPrefix_format_check"
CHECK ("trackingPrefix" ~ '^[A-Z0-9]{3,5}$');

CREATE UNIQUE INDEX "Organization_trackingPrefix_key"
ON "Organization"("trackingPrefix");

CREATE FUNCTION prevent_tracking_prefix_change()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW."trackingPrefix" IS DISTINCT FROM OLD."trackingPrefix" THEN
    RAISE EXCEPTION 'Organization tracking prefixes are permanent';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER "Organization_trackingPrefix_immutable"
BEFORE UPDATE OF "trackingPrefix" ON "Organization"
FOR EACH ROW EXECUTE FUNCTION prevent_tracking_prefix_change();

ALTER TABLE "Customer"
ADD COLUMN "organizationId" TEXT;

ALTER TABLE "Parcel"
ADD COLUMN "organizationId" TEXT,
ADD COLUMN "trackingSequence" BIGINT;

UPDATE "Parcel" AS parcel
SET "organizationId" = COALESCE(
  (SELECT creator."organizationId" FROM "User" AS creator WHERE creator."id" = parcel."createdById"),
  (SELECT location."organizationId" FROM "Location" AS location WHERE location."id" = parcel."locationId"),
  (
    SELECT organization."id"
    FROM "Organization" AS organization
    WHERE (SELECT COUNT(*) FROM "Organization") = 1
    ORDER BY organization."createdAt", organization."id"
    LIMIT 1
  )
);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM "Parcel" WHERE "organizationId" IS NULL) THEN
    RAISE EXCEPTION 'Could not assign every existing parcel to an organization';
  END IF;
END $$;

UPDATE "Customer" AS customer
SET "organizationId" = COALESCE(
  (SELECT account."organizationId" FROM "User" AS account WHERE account."id" = customer."userId"),
  (
    SELECT parcel."organizationId"
    FROM "Parcel" AS parcel
    WHERE parcel."customerId" = customer."id"
    ORDER BY parcel."createdAt", parcel."id"
    LIMIT 1
  ),
  (
    SELECT organization."id"
    FROM "Organization" AS organization
    WHERE (SELECT COUNT(*) FROM "Organization") = 1
    ORDER BY organization."createdAt", organization."id"
    LIMIT 1
  )
)
WHERE customer."organizationId" IS NULL;

UPDATE "Customer" AS customer
SET "organizationId" = (
  SELECT parcel."organizationId"
  FROM "Parcel" AS parcel
  WHERE parcel."customerId" = customer."id"
  ORDER BY parcel."createdAt", parcel."id"
  LIMIT 1
)
WHERE customer."organizationId" IS NULL
  AND EXISTS (
    SELECT 1 FROM "Parcel" AS parcel WHERE parcel."customerId" = customer."id"
  );

UPDATE "Customer"
SET "organizationId" = (
  SELECT "id" FROM "Organization" ORDER BY "createdAt", "id" LIMIT 1
)
WHERE "organizationId" IS NULL
  AND (SELECT COUNT(*) FROM "Organization") = 1;

ALTER TABLE "Customer"
ADD CONSTRAINT "Customer_organizationId_fkey"
FOREIGN KEY ("organizationId") REFERENCES "Organization"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "Parcel"
ALTER COLUMN "organizationId" SET NOT NULL,
ADD CONSTRAINT "Parcel_organizationId_fkey"
FOREIGN KEY ("organizationId") REFERENCES "Organization"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE UNIQUE INDEX "Parcel_organizationId_trackingSequence_key"
ON "Parcel"("organizationId", "trackingSequence");

CREATE INDEX "Parcel_organizationId_createdAt_idx"
ON "Parcel"("organizationId", "createdAt");

CREATE INDEX "Customer_organizationId_idx"
ON "Customer"("organizationId");
