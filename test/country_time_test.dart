import 'package:flutter_test/flutter_test.dart';
import 'package:d2f_application/core/country_time.dart';

void main() {
  test('Connect uses route country and regional US time zones', () {
    expect(suggestedTimezone('New York, USA'), 'America/New_York');
    expect(suggestedTimezone('Omaha, NE, USA'), 'America/Chicago');
    expect(suggestedTimezone('Lomé, Togo'), 'Africa/Lome');
    expect(suggestedTimezone('USA'), isNull);
    expect(
      countryDate('2026-12-15T17:00:00Z', timezone: 'America/New_York'),
      contains('12:00 PM'),
    );
    expect(
      countryDate('2026-07-15T16:00:00Z', timezone: 'America/New_York'),
      contains('12:00 PM'),
    );
    expect(
      countryDate('2026-12-15T17:00:00Z', timezone: 'Africa/Lome'),
      contains('5:00 PM'),
    );
    expect(
      countryDateStart(DateTime(2026, 12, 15), 'America/New_York'),
      DateTime.utc(2026, 12, 15, 5),
    );
    expect(
      countryDateStart(DateTime(2026, 7, 15), 'America/New_York'),
      DateTime.utc(2026, 7, 15, 4),
    );
  });
}
