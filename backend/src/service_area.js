// Agreed operating countries. Suggestions do not imply a warehouse exists.
export const SERVICE_COUNTRIES = [
  'United States', 'Belgium', 'France', 'Togo', 'Benin', 'Burkina Faso',
  'Gabon', 'Ghana', 'Senegal', 'Nigeria', 'Côte d’Ivoire',
];
export const COUNTRY_TIMEZONES = {
  'United States': 'America/Chicago', Belgium: 'Europe/Brussels', France: 'Europe/Paris',
  Togo: 'Africa/Lome', Benin: 'Africa/Porto-Novo', 'Burkina Faso': 'Africa/Ouagadougou',
  Gabon: 'Africa/Libreville', Ghana: 'Africa/Accra', Senegal: 'Africa/Dakar',
  Nigeria: 'Africa/Lagos', 'Côte d’Ivoire': 'Africa/Abidjan',
};
export function countryInLocation(value) {
  if (typeof value !== 'string') return null;
  const normalized = value.toLowerCase();
  if (/\busa\b|united states/.test(normalized)) return 'United States';
  return SERVICE_COUNTRIES.find(country => normalized.includes(country.toLowerCase())) || null;
}
