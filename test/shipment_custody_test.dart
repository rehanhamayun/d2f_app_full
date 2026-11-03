import 'dart:io';
import 'dart:ui' as ui;

import 'package:d2f_application/core/theme.dart';
import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/screens/shipment_custody_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'PlusJakartaSans',
    )..addFont(rootBundle.load('assets/fonts/PlusJakartaSans.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'assigned driver confirms collection without setting warehouse receipt',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, dynamic>? sent;
      var done = false;
      Future<dynamic> request(
        String path, {
        String method = 'GET',
        Map<String, dynamic>? data,
      }) async {
        if (method == 'POST') {
          sent = data;
          done = true;
          return {'status': 'PICKED_UP'};
        }
        return done
            ? []
            : [
                {
                  'id': 'p1',
                  'trackingId': 'D2F000000000123',
                  'status': 'PICKUP_SCHEDULED',
                  'pickupAddress': 'Customer collection point · Omaha',
                  'contactName': 'Mary Morgan',
                  'contactPhone': '+14025550111',
                  'pickupScheduledAt': DateTime.now()
                      .add(const Duration(hours: 2))
                      .toIso8601String(),
                  'items': [
                    {
                      'id': 'i1',
                      'name': 'Clothing box',
                      'quantity': 2,
                      'type': 'BOX',
                    },
                  ],
                },
              ];
      }

      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          builder: (context, child) =>
              RepaintBoundary(key: boundary, child: child!),
          home: Scaffold(body: DriverTasksScreen(request: request)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final img =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory('design/verification-custody').createSync(recursive: true);
        File('design/verification-custody/01-driver-assignments.png')
            .writeAsBytesSync(png!.buffer.asUint8List());
        img.dispose();
      });
      await tester.tap(find.text('Confirm physical pickup'));
      await tester.pumpAndSettle();
      Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      );
      await tester.enterText(
        field('Scan / enter D2F tracking number'),
        'D2F000000000123',
      );
      await tester.enterText(
        field('Handover / identity / proof reference'),
        'Sender handover receipt REF-01',
      );
      await tester.tap(
        find.text(
          'I physically collected these goods. They are in my custody, awaiting warehouse receipt.',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm actual handover'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      expect(sent?['confirmed'], true);
      expect(sent?['scannedTrackingId'], 'D2F000000000123');
      expect(sent?.containsKey('locationId'), false);
      expect(sent?.containsKey('warehouseReceivedAt'), false);
      expect(find.textContaining('No active assignments'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pending and collected shipments expose different staff actions on compact screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final row in [
        ('REQUESTED', 'PICKUP', false),
        ('PICKUP_SCHEDULED', 'PICKUP', false),
        ('PICKED_UP', 'PICKUP', true),
        ('REQUESTED', 'DROP_OFF', true),
      ]) {
        final p = Parcel.fromJson({
          'id': 'p1',
          'trackingId': 'D2F000000000123',
          'customerId': 'c',
          'recipientName': 'Recipient',
          'packageType': 'BOX',
          'weightKg': 5,
          'origin': 'Omaha, USA',
          'destination': 'Lomé, Togo',
          'method': 'SEA',
          'status': row.$1,
          if (row.$1 == 'PICKED_UP')
            'pickupConfirmedAt': DateTime.now().toIso8601String(),
          'deliveryMode': row.$2,
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.3),
                  ),
                  child: ShipmentCustodyCard(parcel: p, onSaved: () async {}),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Scan & verify warehouse receipt'),
          row.$3 ? findsOneWidget : findsNothing,
        );
        expect(find.text('Confirm physical pickup'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'warehouse receipt works on a compact phone without loading driver permissions',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, dynamic>? saved;
      final paths = <String>[];
      final parcel = Parcel.fromJson({
        'id': 'receipt-1',
        'trackingId': 'D2F000000000014',
        'customerId': 'customer-1',
        'recipientName': 'Kossi',
        'packageType': 'BARREL',
        'weightKg': 5,
        'origin': 'Lomé, Togo',
        'destination': 'Omaha, USA',
        'method': 'SEA',
        'status': 'REQUESTED',
        'deliveryMode': 'DROP_OFF',
        'items': [
          {
            'id': 'food-1',
            'name': 'Foodstuff',
            'type': 'BARREL',
            'quantity': 1,
          },
        ],
      });
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          builder: (_, child) =>
              RepaintBoundary(key: boundaryKey, child: child!),
          home: ShipmentCustodyScreen(
            parcel: parcel,
            mode: 'intake',
            request: (path, {method = 'GET', data}) async {
              paths.add(path);
              if (method == 'POST') {
                saved = data;
                throw Exception('Test retry: connection interrupted');
              }
              if (path.startsWith('/operational-notes')) return [];
              return [
                {'id': 'lome-1', 'name': 'Lomé Facility', 'city': 'Lomé'},
              ];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(paths.first, '/warehouse/locations');
      expect(paths.any((p) => p.startsWith('/parcels/drivers')), false);
      final confirm = find.widgetWithText(
        FilledButton,
        'Confirm warehouse receipt',
      );
      expect(confirm.hitTestable(), findsOneWidget);
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final img = await boundary.toImage(pixelRatio: 2);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('design/verification-custody/02-warehouse-receipt.png')
            .writeAsBytesSync(png!.buffer.asUint8List());
        img.dispose();
      });
      final scan = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Scan / enter the D2F tracking number',
      );
      await tester.ensureVisible(scan);
      await tester.enterText(scan, parcel.trackingId);
      await tester.scrollUntilVisible(
        find.text('Operational message *'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('operational-note-RECEIVED')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other - Custom Message').last);
      await tester.pumpAndSettle();
      final note = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Custom operational message *',
      );
      await tester.ensureVisible(note);
      await tester.enterText(note, 'Sealed and undamaged');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Foodstuff'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Foodstuff'));
      await tester.scrollUntilVisible(
        find.text(
          'I physically verified and confirmed this handover at the selected facility.',
        ),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(
        find.text(
          'I physically verified and confirmed this handover at the selected facility.',
        ),
      );
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(saved?['locationId'], 'lome-1');
      expect(saved?['scannedTrackingId'], parcel.trackingId);
      expect(saved?['verifiedItemIds'], ['food-1']);
      expect(find.text('Sealed and undamaged'), findsOneWidget);
      expect(find.textContaining('connection interrupted'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
