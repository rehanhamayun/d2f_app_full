export const CATEGORIES = ['CLOTHING', 'PHONE', 'LAPTOP', 'DOCUMENTS', 'OTHER'];
export const ACTIVE_ASSIGNMENTS = ['PROPOSED', 'ACCEPTED', 'CONFIRMED'];
export const routeKey = value => String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/\busa\b|\bus\b/g, 'united states').replace(/[^a-z0-9]/g, '');
export function fail(status, message) { throw Object.assign(new Error(message), { status }); }
export function text(value, field, max = 120) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > max) fail(400, `Enter ${field} (up to ${max} characters).`);
  return value.trim();
}
export function number(value, field, min = 0, max = 100000000, integer = false) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max || (integer && !Number.isSafeInteger(value))) fail(400, `Enter a valid ${field}.`);
  return value;
}
export function future(value, field) {
  const date = new Date(value);
  if (!value || !Number.isFinite(date.getTime()) || date <= new Date() || date > new Date(Date.now() + 366 * 86400000)) fail(400, `Choose ${field} within the next year.`);
  return date;
}
export function quote(rate, { weightKg, quantity }) {
  if (!rate || !rate.isActive || rate.unit === 'MANUAL' || (rate.maxWeightKg != null && weightKg > rate.maxWeightKg)) return null;
  return Math.ceil(rate.amountMinor * (rate.unit === 'KG' ? weightKg : rate.unit === 'ITEM' ? quantity : 1));
}
export const effectiveWeight = booking => booking.verifiedWeightKg ?? booking.parcel.weightKg;
export function matchingError(trip, booking, remainingKg) {
  if (trip.status !== 'APPROVED' || new Date(trip.departureAt) <= new Date()) return 'This trip is not approved for new assignments.';
  if (routeKey(trip.origin) !== routeKey(booking.parcel.origin) || routeKey(trip.destination) !== routeKey(booking.parcel.destination)) return 'The trip route and direction do not match this booking.';
  if (new Date(trip.departureAt) < new Date(booking.preferredDate)) return 'The trip leaves before the customer’s preferred travel date.';
  if (!trip.categories.includes(booking.category)) return 'The traveller does not accept this parcel category.';
  if (effectiveWeight(booking) > remainingKg + 0.00001) return 'The trip does not have sufficient remaining baggage capacity.';
  return null;
}
export function approvedLocationMatches(location, trip) {
  return trip && location?.connectReceiving && location.address && location.city && location.country &&
    routeKey(trip.origin).includes(routeKey(location.city)) && routeKey(trip.origin).includes(routeKey(location.country));
}
