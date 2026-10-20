import { PrismaClient } from '@prisma/client';

// Singleton Prisma client (avoids connection exhaustion in dev reloads)
export const prisma = new PrismaClient();
