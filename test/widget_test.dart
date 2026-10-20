import 'package:flutter_test/flutter_test.dart';

/// Minimal model-level smoke tests for Milestone 1 data mapping.
/// (Widget/UI tests are exercised on-device during acceptance demos.)
import 'package:d2f_application/models/models.dart';

void main() {
  group('Parcel model', () {
    test('parses backend parcel JSON with events + customer', () {
      final parcel = Parcel.fromJson({
        'id': 'uuid-1',
        'trackingId': 'D2F-2026-000104',
        'customerId': 'cust-1',
        'recipientName': 'Test Recipient',
        'packageType': 'BOX',
        'weightKg': 3.2,
        'origin': 'Omaha, NE, USA',
        'destination': 'Lomé, Togo',
        'method': 'AIR',
        'status': 'RECEIVED',
        'createdAt': '2026-10-19T22:19:45.708Z',
        'updatedAt': '2026-10-19T22:19:45.708Z',
        'customer': {'id': 'cust-1', 'displayName': 'Koffi Mensah'},
        'events': [
          {
            'id': 'e1',
            'status': 'RECEIVED',
            'note': 'Parcel registered at intake',
            'location': 'Omaha, NE, USA',
            'createdAt': '2026-10-19T22:19:45.708Z',
            'actor': {'fullName': 'Warehouse Staff'},
          },
        ],
      });

      expect(parcel.trackingId, 'D2F-2026-000104');
      expect(parcel.method, ShippingMethod.AIR);
      expect(parcel.destinationFlag, '🇹🇬');
      expect(parcel.events.length, 1);
      expect(parcel.events.first.actorName, 'Warehouse Staff');
      expect(parcel.packageTypeLabel, 'Box');
    });

    test('parses list-item JSON without customer/events', () {
      final parcel = Parcel.fromJson({
        'id': 'uuid-2',
        'trackingId': 'D2F-2026-000105',
        'customerId': 'cust-1',
        'recipientName': 'X',
        'packageType': 'BARREL',
        'weightKg': 22,
        'origin': 'A',
        'destination': 'Cotonou, Benin',
        'method': 'SEA',
        'status': 'IN_TRANSIT',
      });
      expect(parcel.events, isEmpty);
      expect(parcel.destinationFlag, '🇧🇯');
      expect(statusLabel(parcel.status), 'In Transit');
      expect(statusSubLabel(parcel.status), 'On the way to West Africa');
    });

    test('status transitions map matches backend contract', () {
      expect(
        kAllowedTransitions['RECEIVED'],
        containsAll(['PROCESSING', 'IN_TRANSIT']),
      );
      expect(kAllowedTransitions['DELIVERED'], isEmpty);
    });
  });
}
