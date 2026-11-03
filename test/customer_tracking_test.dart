import 'dart:io';
import 'dart:ui' as ui;

import 'package:d2f_application/core/theme.dart';
import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/providers/auth_provider.dart';
import 'package:d2f_application/screens/customer_shipment_screen.dart';
import 'package:d2f_application/screens/role_workspace_screen.dart';
import 'package:d2f_application/widgets/customer_tracking_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session extends AuthController {
  final UserRole role;
  _Session(this.role);
  @override
  Future<User?> build() async => User(
    id: 'customer',
    fullName: 'Alex Morgan',
    email: 'alex@example.test',
    phone: '+14025550187',
    role: role,
  );
}

Parcel shipment(int i, String status, {String service = 'SEA'}) =>
    Parcel.fromJson({
      'id': 'p$i',
      'trackingId': 'D2F${(i + 1).toString().padLeft(12, '0')}',
      'customerId': 'c1',
      'recipientName': 'Kossi Mensah',
      'origin': 'Omaha, NE, USA',
      'destination': 'Lomé, Togo',
      'method': service == 'SEA' ? 'SEA' : 'AIR',
      'serviceType': service,
      'status': status,
      'createdAt': DateTime.utc(2026, 10, 29 - i).toIso8601String(),
      'updatedAt': DateTime.utc(2026, 10, 29).toIso8601String(),
      if (service == 'AIR_TRAVELLER') 'connectBooking': {'id': 'connect-1'},
    });

void main() {
  setUpAll(() async {
    for (final entry in [
      ('PlusJakartaSans', 'assets/fonts/PlusJakartaSans.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(entry.$1)..addFont(rootBundle.load(entry.$2))).load();
    }
  });

  testWidgets(
    'Track shows all customer statuses and refreshes after viewing a shipment',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final rows = [
        shipment(0, 'REQUESTED'),
        shipment(1, 'PROCESSING'),
        shipment(2, 'IN_TRANSIT'),
        shipment(3, 'DELIVERED'),
        shipment(4, 'TRAVELLER_PROPOSED', service: 'AIR_TRAVELLER'),
      ];
      var loads = 0;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              () => _Session(UserRole.CUSTOMER),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.build(),
            builder: (_, child) =>
                RepaintBoundary(key: boundary, child: child!),
            home: RoleWorkspaceScreen(
              loadCustomerParcels: () async {
                loads++;
                return rows.reversed.toList();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(loads, 0);
      await tester.tap(find.byKey(const ValueKey('nav-activity')));
      await tester.pumpAndSettle();
      expect(loads, 1);
      expect(find.text('Track Shipment'), findsOneWidget);
      expect(find.text('Your shipments'), findsOneWidget);
      for (final row in rows) {
        expect(
          find.byKey(ValueKey('track-shipment-${row.id}')),
          findsOneWidget,
        );
        expect(find.text(statusLabel(row.status)), findsOneWidget);
      }
      await tester.runAsync(() async {
        final img =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory('design/verification-customer').createSync(recursive: true);
        File('design/verification-customer/09-track-all-shipments.png')
            .writeAsBytesSync(png!.buffer.asUint8List());
        img.dispose();
      });
      final first = find.byKey(const ValueKey('track-shipment-p0'));
      await tester.ensureVisible(first);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(find.byType(CustomerParcelDetailsScreen), findsOneWidget);
      expect(find.text('D2F000000000001'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(loads, 2);
      await tester.ensureVisible(find.byTooltip('Refresh your shipments'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh your shipments'));
      await tester.pumpAndSettle();
      expect(loads, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('refresh failure preserves history and retry recovers', (
    tester,
  ) async {
    var fail = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CustomerTrackingHistory(
              loadParcels: () async {
                if (fail) throw Exception('Offline');
                return [shipment(0, 'REQUESTED')];
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    fail = true;
    await tester.tap(find.byTooltip('Refresh your shipments'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not refresh'), findsOneWidget);
    expect(find.byKey(const ValueKey('track-shipment-p0')), findsOneWidget);
    expect(find.text('No shipments yet'), findsNothing);
    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not refresh'), findsNothing);
  });

  testWidgets(
    'empty history and long statuses fit compact phones with larger text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var rows = <Parcel>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: CustomerTrackingHistory(loadParcels: () async => rows),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No shipments yet'), findsOneWidget);
      rows = [shipment(0, 'DOMESTIC_IN_TRANSIT', service: 'AIR_TRAVELLER')];
      await tester.tap(find.byTooltip('Refresh your shipments'));
      await tester.pumpAndSettle();
      expect(find.text('Domestic Shipping in Transit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('driver Track does not request customer history', (tester) async {
    var loads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => _Session(UserRole.DRIVER)),
        ],
        child: MaterialApp(
          theme: AppTheme.build(),
          home: RoleWorkspaceScreen(
            loadCustomerParcels: () async {
              loads++;
              return [];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-activity')));
    await tester.pumpAndSettle();
    expect(loads, 0);
    expect(find.byType(CustomerTrackingHistory), findsNothing);
  });
}
