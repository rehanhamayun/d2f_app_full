/// Agreed EU/USA ↔ African service area. These are supported country choices,
/// not claims that a D2F warehouse exists in every country.
const kServiceCountries = [
  ('🇹🇬', 'Togo', '+228', 8),
  ('🇧🇯', 'Benin', '+229', 10),
  ('🇧🇫', 'Burkina Faso', '+226', 8),
  ('🇬🇦', 'Gabon', '+241', 8),
  ('🇬🇭', 'Ghana', '+233', 9),
  ('🇸🇳', 'Senegal', '+221', 9),
  ('🇳🇬', 'Nigeria', '+234', 10),
  ('🇨🇮', 'Côte d’Ivoire', '+225', 10),
  ('🇺🇸', 'United States', '+1', 10),
  ('🇧🇪', 'Belgium', '+32', 9),
  ('🇫🇷', 'France', '+33', 9),
];
const kCountryLocations = {
  'Togo': 'Lomé, Togo',
  'Benin': 'Cotonou, Benin',
  'Burkina Faso': 'Ouagadougou, Burkina Faso',
  'Gabon': 'Libreville, Gabon',
  'Ghana': 'Accra, Ghana',
  'Senegal': 'Dakar, Senegal',
  'Nigeria': 'Lagos, Nigeria',
  'Côte d’Ivoire': 'Abidjan, Côte d’Ivoire',
  'United States': 'Omaha, NE, USA',
  'Belgium': 'Brussels, Belgium',
  'France': 'Paris, France',
};
String serviceCountryFlag(String destination) {
  final d = destination.toLowerCase();
  if (d.contains('usa') || d.contains('united states')) return '🇺🇸';
  for (final country in kServiceCountries) {
    if (d.contains(country.$2.toLowerCase())) return country.$1;
  }
  return '🌍';
}
