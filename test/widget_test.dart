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
      expect(statusSubLabel(parcel.status), 'On the way to destination');
    });

    test('status transitions map matches backend contract', () {
      expect(kAllowedTransitions['REQUESTED'], [
        'RECEIVED',
        'PICKUP_SCHEDULED',
      ]);
      expect(kAllowedTransitions['PICKUP_SCHEDULED'], ['PICKED_UP']);
      expect(kAllowedTransitions['PICKED_UP'], ['RECEIVED']);
      expect(kAllowedTransitions['RECEIVED'], ['PROCESSING']);
      expect(kAllowedTransitions['PROCESSING'], ['IN_TRANSIT']);
      expect(kAllowedTransitions['READY_FOR_PICKUP'], [
        'DELIVERED',
        'OUT_FOR_DELIVERY',
        'RELEASED',
      ]);
      expect(kAllowedTransitions['DELIVERED'], isEmpty);
    });

    test('drop-off shipments can never enter the pickup-only stages', () {
      final dropOff = Parcel.fromJson({
        'id': 'drop-1',
        'trackingId': 'D2F-2026-000106',
        'customerId': 'cust-1',
        'recipientName': 'X',
        'packageType': 'BOX',
        'weightKg': 4,
        'origin': 'A',
        'destination': 'Lomé, Togo',
        'method': 'SEA',
        'status': 'REQUESTED',
        'deliveryMode': 'DROP_OFF',
      });
      expect(dropOff.deliveryMode, DeliveryMode.DROP_OFF);
      expect(allowedStatusesFor(dropOff), ['RECEIVED']);

      // Warehouse drop-off drops the goods at the facility, so intake is
      // confirmed directly there and never carries a pickup stage.
      expect(kPickupOnlyStatuses, {'PICKUP_SCHEDULED', 'PICKED_UP'});
    });

    test('pickup requests pass through the collection stages', () {
      final pickup = Parcel.fromJson({
        'id': 'pick-1',
        'trackingId': 'D2F-2026-000107',
        'customerId': 'cust-1',
        'recipientName': 'X',
        'packageType': 'BOX',
        'weightKg': 4,
        'origin': 'A',
        'destination': 'Lomé, Togo',
        'method': 'AIR',
        'status': 'REQUESTED',
        'deliveryMode': 'PICKUP',
        'pickupAddress': '108 Dodge Street, Omaha',
        'pickupScheduledAt': '2026-11-15T10:30:00.000Z',
        'items': [
          {
            'id': 'item-1',
            'name': 'Clothing box',
            'quantity': 2,
            'weightKg': 7,
            'position': 0,
          },
        ],
        'images': [
          {
            'id': 'img-1',
            'fileName': 'front.jpg',
            'contentType': 'image/jpeg',
            'sizeBytes': 12345,
            'createdAt': '2026-10-22T08:00:00.000Z',
          },
        ],
      });

      expect(pickup.deliveryMode, DeliveryMode.PICKUP);
      expect(pickup.totalPieces, 2);
      expect(pickup.pickupScheduledAt, DateTime.utc(2026, 11, 15, 10, 30));
      expect(allowedStatusesFor(pickup), ['PICKUP_SCHEDULED']);
      expect(pickup.items.single.name, 'Clothing box');
      expect(pickup.images.single.fileName, 'front.jpg');
      // Item-to-create round trip carries the goods contract.
      final draft = pickup.items.single.toCreateJson();
      expect(draft['name'], 'Clothing box');
      expect(draft['quantity'], 2);
      expect(draft['weightKg'], 7);
    });
  });
}
