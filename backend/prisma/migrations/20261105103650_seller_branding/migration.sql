-- AlterTable
ALTER TABLE "SellerProfile" ADD COLUMN     "banner" BYTEA,
ADD COLUMN     "bannerName" TEXT DEFAULT '',
ADD COLUMN     "profilePicture" BYTEA,
ADD COLUMN     "profilePictureName" TEXT DEFAULT '';
