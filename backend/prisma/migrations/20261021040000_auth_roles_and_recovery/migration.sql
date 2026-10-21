ALTER TABLE "User" ALTER COLUMN "role" SET DEFAULT 'CUSTOMER';
ALTER TABLE "User" ADD COLUMN "authVersion" INTEGER NOT NULL DEFAULT 0;
CREATE TABLE "SocialIdentity" (
  "id" TEXT NOT NULL, "provider" TEXT NOT NULL, "subject" TEXT NOT NULL, "userId" TEXT NOT NULL,
  CONSTRAINT "SocialIdentity_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "SocialIdentity_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "SocialIdentity_provider_subject_key" ON "SocialIdentity"("provider", "subject");
CREATE TABLE "PasswordReset" (
  "id" TEXT NOT NULL, "userId" TEXT, "codeHash" TEXT NOT NULL, "authVersion" INTEGER NOT NULL,
  "attempts" INTEGER NOT NULL DEFAULT 0, "expiresAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "PasswordReset_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "PasswordReset_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX "PasswordReset_expiresAt_idx" ON "PasswordReset"("expiresAt");
CREATE TABLE "SocialLoginFlow" (
  "id" TEXT NOT NULL, "provider" TEXT NOT NULL, "secretHash" TEXT NOT NULL,
  "stateHash" TEXT NOT NULL, "nonce" TEXT NOT NULL, "verifier" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending', "userId" TEXT, "error" TEXT, "expiresAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "SocialLoginFlow_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "SocialLoginFlow_stateHash_key" ON "SocialLoginFlow"("stateHash");
CREATE INDEX "SocialLoginFlow_expiresAt_idx" ON "SocialLoginFlow"("expiresAt");
