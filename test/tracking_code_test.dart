import 'package:d2f_application/core/tracking_code.dart';
import 'package:d2f_application/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeTrackingCode', () {
    test('accepts the current organization-prefixed identity', () {
      expect(normalizeTrackingCode('D2F000000000005'), 'D2F000000000005');
    });

    test('normalizes lower case, spaces, separators and scanner noise', () {
      expect(
        normalizeTrackingCode('  d2f-000000000005 \n'),
        'D2F000000000005',
      );
      expect(
        normalizeTrackingCode('D2F 0000 0000 0005'),
        'D2F000000000005',
      );
    });

    test('extracts the identity from QR URLs and JSON payloads', () {
      expect(
        normalizeTrackingCode(
          'https://d2fshipping.com/track/D2F000000000005?source=label',
        ),
        'D2F000000000005',
      );
      expect(
        normalizeTrackingCode('{"trackingId":"D2F000000000005"}'),
        'D2F000000000005',
      );
      expect(
        normalizeTrackingCode(
          'https%3A%2F%2Fd2fshipping.com%2Ftrack%2FD2F000000000005',
        ),
        'D2F000000000005',
      );
    });

    test('supports legacy dashed identities and numeric-only barcodes', () {
      expect(normalizeTrackingCode('D2F-2026-000101'), 'D2F-2026-000101');
      expect(normalizeTrackingCode('000000000005'), 'D2F000000000005');
      expect(normalizeTrackingCode('000000000000005'), 'D2F000000000000005');
    });

    test('rejects empty and non-D2F payloads', () {
      expect(normalizeTrackingCode(null), isNull);
      expect(normalizeTrackingCode('   '), isNull);
      expect(normalizeTrackingCode('https://example.com/hello'), isNull);
      expect(normalizeTrackingCode('12345'), isNull);
    });
  });

  group('route rules', () {
    test('air and sea require different cities', () {
      expect(
        validateRouteSelection(
          origin: 'Lomé, Togo',
          destination: 'Lome, Togo',
          method: ShippingMethod.AIR,
        ),
        contains('different origin and destination'),
      );
      expect(
        validateRouteSelection(
          origin: 'Omaha, NE, USA',
          destination: 'Lomé, Togo',
          method: ShippingMethod.SEA,
        ),
        isNull,
      );
    });

    test('same-city road delivery needs two different addresses', () {
      expect(
        validateRouteSelection(
          origin: 'Lomé, Togo',
          destination: 'Lomé, Togo',
          method: ShippingMethod.ROAD,
          pickupAddress: '',
          recipientAddress: 'Rue du Marché 10',
        ),
        contains('both a pickup address'),
      );
      expect(
        validateRouteSelection(
          origin: 'Lomé, Togo',
          destination: 'Lomé, Togo',
          method: ShippingMethod.ROAD,
          pickupAddress: 'Boulevard du 13 Janvier 4',
          recipientAddress: 'Boulevard du 13 Janvier 4',
        ),
        contains('must be different'),
      );
      expect(
        validateRouteSelection(
          origin: 'Lomé, Togo',
          destination: 'Lomé, Togo',
          method: ShippingMethod.ROAD,
          pickupAddress: 'Boulevard du 13 Janvier 4',
          recipientAddress: 'Rue du Marché 10',
        ),
        isNull,
      );
    });

    test('different-city road routes do not require a pickup address', () {
      expect(
        validateRouteSelection(
          origin: 'Lomé, Togo',
          destination: 'Kara, Togo',
          method: ShippingMethod.ROAD,
        ),
        isNull,
      );
    });
  });
}
