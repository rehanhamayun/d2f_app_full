// IANA identifiers preserve daylight-saving rules. Multi-zone countries require
// a city match or an explicit choice; unknown routes are never called US time.
export const COUNTRY_ZONES = {
  'United States': ['America/New_York', 'America/Chicago', 'America/Denver', 'America/Phoenix', 'America/Los_Angeles', 'America/Anchorage', 'Pacific/Honolulu'],
  Belgium: ['Europe/Brussels'], France: ['Europe/Paris'], Togo: ['Africa/Lome'],
  Benin: ['Africa/Porto-Novo'], 'Burkina Faso': ['Africa/Ouagadougou'],
  Gabon: ['Africa/Libreville'], Ghana: ['Africa/Accra'], Senegal: ['Africa/Dakar'],
  Nigeria: ['Africa/Lagos'], 'Côte d’Ivoire': ['Africa/Abidjan'],
};
const normalize = s => String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[’']/g, '');
export function routeCountry(route) {
  const value = normalize(route);
  if (/\b(usa|us)\b|united states/.test(value)) return 'United States';
  return Object.keys(COUNTRY_ZONES).find(c => value.includes(normalize(c))) || null;
}
export function inferredZone(route) {
  const country = routeCountry(route);
  if (country !== 'United States') return COUNTRY_ZONES[country]?.[0] || null;
  const value = normalize(route);
  const cities = [
    [/new york|atlanta|miami|boston|washington|philadelphia|detroit/, 'America/New_York'],
    [/omaha|chicago|houston|dallas|austin|minneapolis|nashville/, 'America/Chicago'],
    [/denver|salt lake/, 'America/Denver'], [/phoenix|tucson/, 'America/Phoenix'],
    [/los angeles|san francisco|seattle|las vegas|san diego|portland/, 'America/Los_Angeles'],
    [/anchorage/, 'America/Anchorage'], [/honolulu/, 'Pacific/Honolulu'],
  ];
  return cities.find(([pattern]) => pattern.test(value))?.[1] || null;
}
export function routeZone(route, selected) {
  const country = routeCountry(route);
  const zone = selected || inferredZone(route);
  if (!zone || !COUNTRY_ZONES[country]?.includes(zone)) throw Object.assign(new Error('Choose a time zone for the route country. For the USA, select the departure city’s time zone.'), { status: 400 });
  return zone;
}
const parts = (date, zone) => Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: zone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit' }).formatToParts(date).filter(p => p.type !== 'literal').map(p => [p.type, Number(p.value)]));
const wall = p => Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second || 0);
export function localToInstant(value, zone, occurrence) {
  if (occurrence && !['EARLIER', 'LATER'].includes(occurrence)) throw Object.assign(new Error('Choose the first or second occurrence of this clock time.'), { status: 400 });
  if (typeof value !== 'string' || !/^\d{4}-\d\d-\d\dT\d\d:\d\d(:\d\d)?$/.test(value)) throw Object.assign(new Error('Enter a local departure date and time.'), { status: 400 });
  const target = new Date(value + 'Z');
  if (!Number.isFinite(target.getTime()) || target.toISOString().slice(0,16) !== value.slice(0,16)) throw Object.assign(new Error('Enter a valid departure date.'), { status: 400 });
  const offsets = new Set();
  for (let h = -36; h <= 36; h += 6) {
    const sample = new Date(target.getTime() + h * 3600000);
    offsets.add(wall(parts(sample, zone)) - sample.getTime());
  }
  const candidates = [...offsets].map(offset => new Date(target.getTime() - offset)).filter(d => wall(parts(d, zone)) === target.getTime());
  candidates.sort((a, b) => a - b);
  if (candidates.length === 2 && occurrence) return candidates[occurrence === 'EARLIER' ? 0 : 1];
  if (candidates.length !== 1) throw Object.assign(new Error(candidates.length ? 'This time occurs twice when daylight saving ends. Choose an unambiguous departure time or submit an explicit UTC offset.' : 'This local time does not exist due to daylight saving. Choose another time.'), { status: 400 });
  return candidates[0];
}
export function tripTiming(t) {
  const departureTimezone = t.departureTimezone || inferredZone(t.origin);
  const destinationTimezone = t.destinationTimezone || inferredZone(t.destination);
  const display = zone => t.departureAt && zone ? new Intl.DateTimeFormat('en-US', { timeZone: zone, dateStyle: 'medium', timeStyle: 'short' }).format(new Date(t.departureAt)) + ` · ${zone}` : null;
  return { departureTimezone, destinationTimezone, departureLocal: display(departureTimezone), departureAtDestination: display(destinationTimezone) };
}

export function dashboardTimezone() {
  const saved = globalThis.localStorage?.getItem('d2f-timezone') || 'America/Chicago';
  try { new Intl.DateTimeFormat('en-US', { timeZone: saved }); return saved; } catch { return 'UTC'; }
}
export const zonedDate = (value, zone = dashboardTimezone()) => value ? new Date(value).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short', timeZone: zone }) + ` · ${zone}` : 'Awaiting confirmation';
export const tripDate = trip => trip?.departureLocal || zonedDate(trip?.departureAt, trip?.departureTimezone || inferredZone(trip?.origin) || 'UTC');
