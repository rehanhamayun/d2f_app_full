import 'package:d2f_application/core/theme.dart';
import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/models/warehouse.dart';
import 'package:d2f_application/screens/update_status_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Parcel parcelWithStatus(String status, {String? deliveryMode}) =>
    Parcel.fromJson({
      'id': 'parcel-1',
      'trackingId': 'D2F000000000005',
      'customerId': 'customer-1',
      'recipientName': 'Kossi Mensah',
      'recipientPhone': '+228 90000000',
      'recipientAddress': 'Rue du Marché 10, Lomé',
      'pickupAddress': 'Boulevard du 13 Janvier 4, Lomé',
      'packageType': 'BOX',
      'weightKg': 2.5,
      'origin': 'Lomé, Togo',
      'destination': 'Lomé, Togo',
      'method': 'ROAD',
      'status': status,
      if (deliveryMode != null) 'deliveryMode': deliveryMode,
      'createdAt': '2026-10-18T09:00:00Z',
      'updatedAt': '2026-10-21T10:00:00Z',
      'releasedToName': 'Ama Boateng',
      'releasedToIdNumber': 'TG-12345',
    });

final location = WarehouseLocation.fromJson({
  'id': 'loc-1',
  'name': 'Lomé Facility',
  'code': 'LOM-1',
  'city': 'Lomé',
  'country': 'Togo',
});

Future<void> pumpScreen(WidgetTester tester, Parcel parcel) async {
  await tester.pumpWidget(
    // UniqueKey so a second pumpScreen replaces the whole State instead of
    // reusing the previous screen's precomputed allowed transitions.
    MaterialApp(
      theme: AppTheme.build(),
      home: UpdateStatusScreen(
        key: UniqueKey(),
        parcel: parcel,
        loadLocations: () async => [location],
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('physical updates require a facility and confirmation', (
    tester,
  ) async {
    await pumpScreen(tester, parcelWithStatus('REQUESTED'));

    await tester.tap(find.text('Received'));
    await tester.pumpAndSettle();

    expect(find.text('Facility'), findsOneWidget);
    expect(find.textContaining('Lomé Facility'), findsOneWidget);
    expect(find.text('I physically verified this shipment'), findsOneWidget);
    expect(find.textContaining('Only the facility'), findsOneWidget);
  });

  testWidgets('released handover captures recipient, reference and time', (
    tester,
  ) async {
    await pumpScreen(tester, parcelWithStatus('READY_FOR_PICKUP'));

    await tester.tap(find.text('Released'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Handover date and time'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Handover details'), findsOneWidget);
    expect(find.text('Received by'), findsOneWidget);
    expect(find.text('Handover ID / reference'), findsOneWidget);
    expect(find.text('Handover date and time'), findsOneWidget);
  });

  testWidgets('delivery requires proof type, reference and recipient', (
    tester,
  ) async {
    await pumpScreen(tester, parcelWithStatus('RELEASED'));

    await tester.tap(find.text('Delivered'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Delivery date and time'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Proof of delivery'), findsOneWidget);
    expect(find.text('Delivered to'), findsOneWidget);
    expect(find.text('Proof type'), findsOneWidget);
    expect(find.text('Proof reference'), findsOneWidget);
    expect(find.text('Delivery date and time'), findsOneWidget);
    expect(find.text('Ama Boateng'), findsOneWidget);
  });

  testWidgets('operational notes allow up to 1,000 characters', (tester) async {
    await pumpScreen(tester, parcelWithStatus('READY_FOR_PICKUP'));
    final note = tester.widget<TextField>(find.byType(TextField).last);
    expect(note.maxLength, 1000);
  });

  testWidgets('drop-off request offers only warehouse intake, pickup offers both',
    (tester) async {
    // Default (legacy) records are drop-offs: a REQUESTED shipment can only be
    // received at the warehouse.
    await pumpScreen(tester, parcelWithStatus('REQUESTED'));
    expect(find.text('Received'), findsOneWidget);
    expect(find.text('Pickup Scheduled'), findsNothing);
    expect(find.text('Picked Up'), findsNothing);

    // A customer-requested pickup adds the scheduling and collection steps.
    final pickup = parcelWithStatus('REQUESTED', deliveryMode: 'PICKUP');
    await pumpScreen(tester, pickup);
    expect(find.text('Pickup Scheduled'), findsOneWidget);
    expect(find.text('Picked Up'), findsOneWidget);
    expect(find.text('Received'), findsOneWidget);
  });
}
