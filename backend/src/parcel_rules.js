import { countryInLocation } from './service_area.js';

// Forward-only operational lifecycle. Received → In transit now always passes
// through Processing; physical departure/arrival is confirmed with a facility.
// Customer pickup requests can additionally be scheduled and then collected:
// REQUESTED → PICKUP_SCHEDULED → PICKED_UP → RECEIVED (warehouse intake).
// Drop-off requests skip those pickup stages entirely.
export const PARCEL_TRANSITIONS = {
  REQUESTED: ['RECEIVED', 'PICKUP_SCHEDULED', 'PICKED_UP'],
  PICKUP_SCHEDULED: ['PICKED_UP', 'RECEIVED'],
  PICKED_UP: ['RECEIVED'],
  RECEIVED: ['PROCESSING'],
  PROCESSING: ['IN_TRANSIT'],
  IN_TRANSIT: ['ARRIVED_LOME', 'ARRIVED_DESTINATION'],
  ARRIVED_LOME: ['READY_FOR_PICKUP'],
  ARRIVED_DESTINATION: ['READY_FOR_PICKUP'],
  READY_FOR_PICKUP: ['RELEASED'],
  RELEASED: ['DELIVERED'],
  DELIVERED: [],
};

// Statuses that only make sense when D2F collects the goods from the customer.
export const PICKUP_ONLY_STATUSES = new Set(['PICKUP_SCHEDULED', 'PICKED_UP']);

/**
 * Mode-aware allowed transitions. A drop-off shipment can never be scheduled
 * for pickup or marked picked up; drop-off intake is confirmed directly with
 * RECEIVED at the warehouse. Legacy records default to drop-off.
 */
export function allowedTransitionsFor(parcel) {
  const base = PARCEL_TRANSITIONS[parcel?.status] || [];
  if (parcel?.deliveryMode === 'PICKUP') return [...base];
  return base.filter((status) => !PICKUP_ONLY_STATUSES.has(status));
}

// Pickup stages happen at the customer's door or in transit to the warehouse,
// before the goods reach a facility, so they are neither facility-confirmed
// nor part of the physical-verification acknowledgement below.
export const EDITABLE_REQUEST_STATUSES = new Set([
  'REQUESTED',
  'PICKUP_SCHEDULED',
  'PICKED_UP',
]);

export const PHYSICAL_STATUSES = new Set([
  'RECEIVED',
  'PROCESSING',
  'IN_TRANSIT',
  'ARRIVED_LOME',
  'ARRIVED_DESTINATION',
  'READY_FOR_PICKUP',
  'RELEASED',
  'DELIVERED',
]);

export const CONFIRMATION_STATUSES = new Set([
  'RECEIVED',
  'IN_TRANSIT',
  'ARRIVED_LOME',
  'ARRIVED_DESTINATION',
  'READY_FOR_PICKUP',
  'RELEASED',
  'DELIVERED',
]);

export const DELIVERY_PROOF_TYPES = [
  'SIGNATURE',
  'PHOTO',
  'ID_CONFIRMATION',
  'RECIPIENT_CONFIRMATION',
];

export function normalizePlace(value) {
  return String(value ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

export function cityFromLocation(value) {
  if (typeof value !== 'string') return '';
  return normalizePlace(value.split(',')[0]);
}

export function sameCity(a, b) {
  const left = cityFromLocation(a);
  const right = cityFromLocation(b);
  return Boolean(left && right && left === right);
}

function normalizeAddress(value) {
  return normalizePlace(value).replace(/\s+/g, ' ');
}

/**
 * Air and sea require two different cities. Road may use one city when the
 * pickup and delivery addresses are genuinely different (for example a Lomé
 * collection and a Lomé drop-off). Domestic road routes are city-to-city.
 */
export function validateRoute({ origin, destination, method, pickupAddress, recipientAddress }) {
  if (!['AIR', 'SEA', 'ROAD'].includes(method)) {
    return 'method must be one of AIR, SEA, ROAD';
  }
  if (!sameCity(origin, destination)) return null;
  if (method === 'ROAD') {
    if (!pickupAddress?.trim() || !recipientAddress?.trim()) {
      return 'Same-city road deliveries require both a pickup address and a delivery address.';
    }
    if (normalizeAddress(pickupAddress) === normalizeAddress(recipientAddress)) {
      return 'Pickup and delivery addresses must be different for a same-city road delivery.';
    }
    return null;
  }
  return 'Air and sea shipments require different origin and destination cities.';
}

export function isLomeLocation(location) {
  if (!location) return false;
  const text = normalizePlace(`${location.city || ''} ${location.name || ''} ${location.country || ''}`);
  return text.includes('togo') && text.includes('lome');
}

/**
 * A pickup/release facility must be the parcel's actual destination facility,
 * not merely any dropdown value. Country-only destinations accept any facility
 * in that country; city destinations require the matching city.
 */
export function destinationMatchesLocation(destination, location) {
  if (!location) return false;
  const destinationCountry = countryInLocation(destination);
  if (destinationCountry && location.country && destinationCountry !== location.country) {
    return false;
  }
  const hasCity = typeof destination === 'string' && destination.includes(',');
  if (!hasCity) return true;
  const destinationCity = cityFromLocation(destination);
  const facilityCity = cityFromLocation(location.city || location.name);
  if (!destinationCity || !facilityCity) return false;
  return destinationCity === facilityCity;
}

export function isFacilityAuthorized(user, location) {
  if (!location) return false;
  if (user.role === 'ADMIN') return true;
  return Boolean(user.locationId && user.locationId === location.id);
}

export function facilityDeniedMessage(location) {
  return `Your account is not authorized to confirm operations at ${location?.name || 'this facility'}. Ask an administrator to assign your warehouse.`;
}

/**
 * Resolve either a location UUID from the app or a legacy human-readable
 * facility label. Unknown labels are rejected rather than silently accepted.
 */
export async function resolveFacility(tx, organizationId, { locationId, location }) {
  if (locationId) {
    return tx.location.findFirst({ where: { id: locationId, organizationId } });
  }
  if (typeof location !== 'string' || !location.trim()) return null;
  const label = normalizePlace(location);
  const locations = await tx.location.findMany({ where: { organizationId } });
  return locations.find((candidate) => {
    const candidates = [
      candidate.name,
      candidate.code,
      candidate.city,
      [candidate.city, candidate.country].filter(Boolean).join(', '),
      [candidate.name, candidate.city, candidate.country].filter(Boolean).join(', '),
    ].filter(Boolean).map(normalizePlace);
    return candidates.some((value) => value === label || label.includes(value));
  }) || null;
}

export function validDate(value, { futureToleranceMs = 5 * 60 * 1000 } = {}) {
  if (typeof value !== 'string' || !value.trim()) return null;
  const parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime())) return null;
  if (parsed.getTime() > Date.now() + futureToleranceMs) return null;
  return parsed;
}

/**
 * Customer pickup requests schedule a future collection. Accepts an ISO date
 * string up to 90 days ahead; the returned date is either null (invalid) or
 * the parsed value. No tolerance here: pickups must genuinely be in the
 * future, never in the past.
 */
export function validFutureDate(value, { maxDaysAhead = 90, minMinutesAhead = 60 } = {}) {
  if (typeof value !== 'string' || !value.trim()) return null;
  const parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime())) return null;
  const now = Date.now();
  if (parsed.getTime() < now + minMinutesAhead * 60 * 1000) return null;
  if (parsed.getTime() > now + maxDaysAhead * 24 * 60 * 60 * 1000) return null;
  return parsed;
}
