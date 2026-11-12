import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;

const countryTimezones = {
  'United States': [
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Phoenix',
    'America/Los_Angeles',
    'America/Anchorage',
    'Pacific/Honolulu',
  ],
  'Belgium': ['Europe/Brussels'],
  'France': ['Europe/Paris'],
  'Togo': ['Africa/Lome'],
  'Benin': ['Africa/Porto-Novo'],
  'Burkina Faso': ['Africa/Ouagadougou'],
  'Gabon': ['Africa/Libreville'],
  'Ghana': ['Africa/Accra'],
  'Senegal': ['Africa/Dakar'],
  'Nigeria': ['Africa/Lagos'],
  'Côte d’Ivoire': ['Africa/Abidjan'],
};
String? countryForRoute(String route) {
  final v = route.toLowerCase();
  if (RegExp(r'\b(usa|us)\b|united states').hasMatch(v)) return 'United States';
  for (final country in countryTimezones.keys) {
    if (v.contains(country.toLowerCase())) return country;
  }
  return null;
}

String? suggestedTimezone(String route) {
  final zones = countryTimezones[countryForRoute(route)];
  if (zones == null) return null;
  if (zones.length == 1) return zones.first;
  final v = route.toLowerCase();
  for (final e in {
    r'new york|atlanta|miami|boston|washington|philadelphia|detroit':
        'America/New_York',
    r'omaha|chicago|houston|dallas|austin|minneapolis|nashville':
        'America/Chicago',
    r'denver|salt lake': 'America/Denver',
    r'phoenix|tucson': 'America/Phoenix',
    r'los angeles|san francisco|seattle|las vegas|san diego|portland':
        'America/Los_Angeles',
    r'anchorage': 'America/Anchorage',
    r'honolulu': 'Pacific/Honolulu',
  }.entries) {
    if (RegExp(e.key).hasMatch(v)) return e.value;
  }
  return null;
}

bool _zonesReady = false;
String countryDate(dynamic value, {String? timezone}) {
  final date = DateTime.tryParse('$value');
  if (date == null) return 'Date pending';
  if (!_zonesReady) {
    data.initializeTimeZones();
    _zonesReady = true;
  }
  final zone = timezone ?? 'UTC';
  try {
    final local = tz.TZDateTime.from(date, tz.getLocation(zone));
    return '${DateFormat('MMM d, yyyy · h:mm a').format(local)} · $zone';
  } catch (_) {
    return '${DateFormat('MMM d, yyyy · h:mm a').format(date.toUtc())} · UTC';
  }
}

String connectTripDate(Map<String, dynamic> trip) => countryDate(
  trip['departureAt'],
  timezone:
      trip['departureTimezone'] as String? ??
      suggestedTimezone('${trip['origin']}'),
);

DateTime countryDateStart(DateTime date, String? timezone) {
  if (!_zonesReady) {
    data.initializeTimeZones();
    _zonesReady = true;
  }
  return tz.TZDateTime(
    tz.getLocation(timezone ?? 'UTC'),
    date.year,
    date.month,
    date.day,
  ).toUtc();
}
