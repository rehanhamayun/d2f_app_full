import 'dart:io';
import 'dart:ui' as ui;

import 'package:d2f_application/core/theme.dart';
import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/screens/customer_shipment_screen.dart';
import 'package:d2f_application/screens/role_workspace_screen.dart';
import 'package:d2f_application/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final customerParcel = Parcel(
  id: 'customer-parcel-id',
  trackingId: 'D2F-2026-000204',
  customerId: 'customer-record-id',
  recipientName: 'Kossi Mensah',
  recipientPhone: '+22890000000',
  recipientAddress: 'Lomé, Togo',
  packageType: 'BOX',
  weightKg: 2.5,
  origin: 'Omaha, NE, USA',
  destination: 'Lomé, Togo',
  method: ShippingMethod.AIR,
  status: 'REQUESTED',
  createdAt: DateTime.utc(2026, 10, 22, 8),
  updatedAt: DateTime.utc(2026, 10, 22, 8),
  events: [
    TrackingEvent(
      id: 'request-event',
      status: 'REQUESTED',
      createdAt: DateTime.utc(2026, 10, 22, 8),
    ),
  ],
);

class _CustomerSession extends AuthController {
  @override
  Future<User?> build() async => const User(
    id: 'customer-user',
    email: 'customer@example.test',
    fullName: 'Alex Morgan',
    role: UserRole.CUSTOMER,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader(
      'PlusJakartaSans',
    )..addFont(rootBundle.load('assets/fonts/PlusJakartaSans.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  void size(WidgetTester tester, Size value, {double scale = 1}) {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Widget wrap(Widget child, GlobalKey boundary) => MaterialApp(
    theme: AppTheme.build(),
    builder: (context, child) => RepaintBoundary(
      key: boundary,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1)),
        child: child!,
      ),
    ),
    home: Scaffold(body: child),
  );

  testWidgets('customer Ship tab opens the self-service shipment form', (
    tester,
  ) async {
    size(tester, const Size(390, 844));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith(_CustomerSession.new)],
        child: MaterialApp(
          theme: AppTheme.build(),
          home: RoleWorkspaceScreen(loadCustomerParcels: () async => []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-ship')));
    await tester.pumpAndSettle();
    expect(find.byType(CustomerShipmentScreen), findsOneWidget);
    expect(find.text('Your next shipment'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer can create and revisit a shipment request', (
    tester,
  ) async {
    size(tester, const Size(390, 844));
    final boundaryKey = GlobalKey();
    var parcelLoadCount = 0;
    Map<String, Object?>? submitted;
    await tester.pumpWidget(
      wrap(
        CustomerShipmentScreen(
          loadParcels: () async {
            parcelLoadCount++;
            return parcelLoadCount > 1 ? [customerParcel] : [];
          },
          createParcel:
              ({
                required recipientName,
                recipientPhone,
                recipientAddress,
                required packageType,
                required weightKg,
                required origin,
                required destination,
                required method,
                notes,
                required clientRequestId,
              }) async {
                submitted = {
                  'recipientName': recipientName,
                  'recipientPhone': recipientPhone,
                  'recipientAddress': recipientAddress,
                  'packageType': packageType,
                  'weightKg': weightKg,
                  'origin': origin,
                  'destination': destination,
                  'method': method,
                  'notes': notes,
                  'clientRequestId': clientRequestId,
                };
                return customerParcel;
              },
        ),
        boundaryKey,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your next shipment'), findsOneWidget);

    final screenshotDirectory = Directory('design/verification-customer')
      ..createSync(recursive: true);
    Future<void> capture(String name) async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${screenshotDirectory.path}/$name.png')
            .writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('06-customer-new-shipment');
    await tester.scrollUntilVisible(
      find.text('Your shipments'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Your shipments'), findsOneWidget);
    expect(
      find.textContaining('Your shipment requests and tracking IDs'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('customer-recipient-name')),
      'Kossi Mensah',
    );
    await tester.enterText(
      find.byKey(const ValueKey('customer-recipient-phone')),
      '+22890000000',
    );
    await tester.enterText(
      find.byKey(const ValueKey('customer-recipient-address')),
      'Lomé, Togo',
    );
    await tester.tap(find.byKey(const ValueKey('customer-package-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Box').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('customer-package-weight')),
      '2.5',
    );

    final submit = find.byKey(const ValueKey('customer-create-shipment'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(submitted?['recipientName'], 'Kossi Mensah');
    expect(submitted?['packageType'], 'BOX');
    expect(submitted?['weightKg'], 2.5);
    expect(submitted?['origin'], 'Omaha, NE, USA');
    expect(submitted?['destination'], 'Lomé, Togo');
    expect(submitted?['method'], 'AIR');
    expect(submitted?['clientRequestId'], isNotEmpty);
    expect(find.text('Request created.'), findsOneWidget);
    expect(find.text('Request submitted'), findsOneWidget);
    expect(find.text(customerParcel.trackingId), findsOneWidget);
    expect(find.text('Request Submitted'), findsOneWidget);
    await capture('07-customer-parcel-created');

    final viewShipments = find.text('View my shipments');
    await tester.scrollUntilVisible(
      viewShipments,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(viewShipments);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('customer-parcel-customer-parcel-id')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer shipment form fits a compact screen with larger text', (
    tester,
  ) async {
    size(tester, const Size(320, 640), scale: 1.2);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: CustomerShipmentScreen(
            loadParcels: () async => [],
            createParcel: ({
              required recipientName,
              recipientPhone,
              recipientAddress,
              required packageType,
              required weightKg,
              required origin,
              required destination,
              required method,
              notes,
              required clientRequestId,
            }) async => customerParcel,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('customer-create-shipment')),
    );
    expect(tester.takeException(), isNull);
  });
}
