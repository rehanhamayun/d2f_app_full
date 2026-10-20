import 'dotenv/config';

const configuredSecret = process.env.JWT_SECRET;
if (process.env.NODE_ENV === 'production' && (!configuredSecret || configuredSecret.length < 32)) {
  throw new Error('Production requires a JWT_SECRET of at least 32 characters.');
}
export const JWT_SECRET = configuredSecret || 'd2f-dev-secret-change-in-production';
