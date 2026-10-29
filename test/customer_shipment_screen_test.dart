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
  recipientAddress: 'Agoe Assiyeye, Lomé',
  packageType: 'BOX',
  weightKg: 2.5,
  origin: 'Omaha, NE, USA',
  destination: 'Lomé, Togo',
  method: ShippingMethod.AIR,
  status: 'REQUESTED',
  deliveryMode: DeliveryMode.DROP_OFF,
  items: [
    const ParcelItem(
      id: 'item-1',
      name: 'Clothing box',
      details: 'Folded summer wear',
      quantity: 2,
      position: 0,
    ),
    const ParcelItem(
      id: 'item-2',
      name: 'Kitchen blender',
      quantity: 1,
      weightKg: 1.2,
      position: 1,
    ),
  ],
  createdAt: DateTime.utc(2026, 10, 22, 8),
  updatedAt: DateTime.utc(2026, 10, 22, 8),
  events: [
    TrackingEvent(
      id: 'request-event',
      status: 'REQUESTED',
      note:
          'Shipment request submitted by customer · goods brought to the '
          'warehouse.',
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
    phone: '+14025550187',
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

  Widget wrap(Widget child, GlobalKey boundary) => ProviderScope(
    overrides: [authControllerProvider.overrideWith(_CustomerSession.new)],
    child: MaterialApp(
      theme: AppTheme.build(),
      builder: (context, child) => RepaintBoundary(
        key: boundary,
        child: MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1)),
          child: child!,
        ),
      ),
      home: Scaffold(body: child),
    ),
  );

  /// Scrolls the shipment form so the keyed widget is fully inside the
  /// viewport before interacting: the form is one long ListView and widget
  /// layout shifts under focus between steps.
  Future<void> reveal(WidgetTester tester, Key key) async {
    final finder = find.byKey(key);
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

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
    expect(find.text('New shipment request'), findsOneWidget);
    // The signed-in customer's phone shows in the contact card so D2F staff
    // can always reach them about this request.
    expect(find.text('+14025550187'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer can create and revisit a shipment request', (
    tester,
  ) async {
    size(tester, const Size(390, 844));
    final boundaryKey = GlobalKey();
    var parcelLoadCount = 0;
    var uploadedItemId = '';
    var detailReloads = 0;
    Map<String, Object?>? submitted;
    await tester.pumpWidget(
      wrap(
        CustomerShipmentScreen(
          pickPhoto: () async => PhotoDraft(
            'books.png',
            'image/png',
            (await rootBundle.load('assets/images/d2f_2.png')).buffer
                .asUint8List(),
          ),
          uploadPhoto: (parcelId, itemId, photo) async {
            expect(parcelId, customerParcel.id);
            expect(photo.fileName, 'books.png');
            uploadedItemId = itemId;
          },
          loadParcel: (id) async {
            detailReloads++;
            return customerParcel;
          },
          loadParcels: () async {
            parcelLoadCount++;
            return parcelLoadCount > 1 ? [customerParcel] : [];
          },
          createParcel:
              ({
                required recipientName,
                required recipientPhone,
                required recipientAddress,
                required packageType,
                required weightKg,
                required origin,
                required destination,
                required method,
                required deliveryMode,
                restrictionsAcknowledged = false,
                pickupAddress,
                pickupScheduledAt,
                items = const [],
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
                  'deliveryMode': deliveryMode,
                  'restrictionsAcknowledged': restrictionsAcknowledged,
                  'pickupAddress': pickupAddress,
                  'items': items,
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
    expect(find.text('New shipment request'), findsOneWidget);

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

    // Goods repeater: physical packages travel with type and dimensions.
    await tester.enterText(
      find.byKey(const ValueKey('goods-size-0')),
      '60x40x45',
    );
    await tester.enterText(
      find.byKey(const ValueKey('goods-name-0')),
      'Clothing box',
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('goods-qty-0')), '2');
    await tester.pumpAndSettle();
    await reveal(tester, const ValueKey('customer-add-item'));
    await tester.tap(find.byKey(const ValueKey('customer-add-item')));
    await tester.pumpAndSettle();
    // A blank draft before this package must not move its photo to another row.
    await reveal(tester, const ValueKey('customer-add-item'));
    await tester.tap(find.byKey(const ValueKey('customer-add-item')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('goods-name-2')),
      'Kitchen blender',
    );
    await reveal(tester, const ValueKey('goods-photo-add-2'));
    await tester.tap(find.byKey(const ValueKey('goods-photo-add-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    await reveal(tester, const ValueKey('customer-recipient-name'));
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
      'Agoe Assiyeye, Lomé',
    );
    await tester.pumpAndSettle();
    await reveal(tester, const ValueKey('customer-package-type'));
    await tester.tap(find.byKey(const ValueKey('customer-package-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Box').last);
    await tester.pumpAndSettle();
    await reveal(tester, const ValueKey('customer-package-weight'));
    await tester.enterText(
      find.byKey(const ValueKey('customer-package-weight')),
      '2.5',
    );

    await reveal(tester, const ValueKey('handover-dropoff'));
    await tester.pumpAndSettle();

    final submit = find.byKey(const ValueKey('customer-create-shipment'));
    await reveal(tester, const ValueKey('customer-create-shipment'));
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(submitted, isNull);
    expect(find.textContaining('Confirm that your goods list'), findsOneWidget);
    await reveal(tester, const ValueKey('customer-restrictions-check'));
    await tester.tap(find.byKey(const ValueKey('customer-restrictions-check')));
    await reveal(tester, const ValueKey('customer-create-shipment'));
    await tester.tap(submit);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(submitted?['restrictionsAcknowledged'], isTrue);
    expect(uploadedItemId, 'item-2');
    expect(detailReloads, 1);

    expect(submitted?['recipientName'], 'Kossi Mensah');
    expect(submitted?['recipientPhone'], '+22890000000');
    expect(submitted?['recipientAddress'], 'Agoe Assiyeye, Lomé');
    expect(submitted?['packageType'], 'BOX');
    expect(submitted?['weightKg'], 2.5);
    expect(submitted?['origin'], 'Omaha, NE, USA');
    expect(submitted?['destination'], 'Lomé, Togo');
    expect(submitted?['method'], 'AIR');
    // Default handover is a warehouse drop-off with no pickup schedule.
    expect(submitted?['deliveryMode'], 'DROP_OFF');
    expect(submitted?['pickupAddress'], isNull);
    final items = submitted?['items'] as List<ParcelItem>;
    expect(items.map((item) => item.name), ['Clothing box', 'Kitchen blender']);
    expect(items.first.quantity, 2);
    expect(items.first.lengthCm, 60);
    expect(items.first.widthCm, 40);
    expect(items.first.heightCm, 45);
    expect(submitted?['clientRequestId'], isNotEmpty);
    expect(find.text('Request created.'), findsOneWidget);
    expect(find.text('Request submitted'), findsOneWidget);
    expect(find.text(customerParcel.trackingId), findsOneWidget);
    // The details screen itemizes the goods under the shipment.
    expect(find.text('Goods in this shipment'), findsOneWidget);
    expect(find.text('Clothing box'), findsOneWidget);
    expect(find.text('×2'), findsOneWidget);
    expect(find.text('Warehouse drop-off'), findsOneWidget);
    expect(find.text('Awaiting Drop-off'), findsOneWidget);
    await capture('07-customer-parcel-created');

    final viewShipments = find.text('View my shipments');
    await tester.scrollUntilVisible(
      viewShipments,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(viewShipments);
    await tester.pumpAndSettle();
    // Back on the shipment workspace; the saved request is listed.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('customer-parcel-customer-parcel-id')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const ValueKey('customer-parcel-customer-parcel-id')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pickup handover requires a collection address and schedule before submit',
    (tester) async {
      size(tester, const Size(390, 844));
      Map<String, Object?>? submitted;
      await tester.pumpWidget(
        wrap(
          CustomerShipmentScreen(
            loadParcels: () async => [],
            selectSchedule: () async => DateTime(2026, 11, 15, 10, 30),
            createParcel:
                ({
                  required recipientName,
                  required recipientPhone,
                  required recipientAddress,
                  required packageType,
                  required weightKg,
                  required origin,
                  required destination,
                  required method,
                  required deliveryMode,
                  restrictionsAcknowledged = false,
                  pickupAddress,
                  pickupScheduledAt,
                  items = const [],
                  notes,
                  required clientRequestId,
                }) async {
                  submitted = {
                    'deliveryMode': deliveryMode,
                    'restrictionsAcknowledged': restrictionsAcknowledged,
                    'pickupAddress': pickupAddress,
                    'pickupScheduledAt': pickupScheduledAt,
                    'items': items,
                  };
                  return customerParcel;
                },
          ),
          GlobalKey(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('goods-name-0')),
        'Carton of books',
      );
      await reveal(tester, const ValueKey('customer-recipient-name'));
      await tester.enterText(
        find.byKey(const ValueKey('customer-recipient-name')),
        'Awa Mensah',
      );
      await tester.enterText(
        find.byKey(const ValueKey('customer-recipient-phone')),
        '+22890000001',
      );
      await tester.enterText(
        find.byKey(const ValueKey('customer-recipient-address')),
        'Agoe, Lomé',
      );
      await tester.pumpAndSettle();
      await reveal(tester, const ValueKey('customer-package-type'));
      await tester.tap(find.byKey(const ValueKey('customer-package-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Box').last);
      await tester.pumpAndSettle();
      await reveal(tester, const ValueKey('customer-package-weight'));
      await tester.enterText(
        find.byKey(const ValueKey('customer-package-weight')),
        '3',
      );

      // Choose the pickup module: the schedule card appears.
      await tester.tap(find.byKey(const ValueKey('handover-pickup')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pickup-details')), findsOneWidget);

      final submit = find.byKey(const ValueKey('customer-create-shipment'));
      await reveal(tester, const ValueKey('customer-create-shipment'));
      // Submitting without the collection address fails client-side and no
      // request is created.
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('Required for a pickup request.'), findsOneWidget);
      expect(submitted, isNull);

      // The collection address fills in; submitting still blocks on the
      // schedule, which is compulsory for a pickup.
      await tester.enterText(
        find.byKey(const ValueKey('customer-pickup-address')),
        '108 Dodge Street, Omaha',
      );
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('Choose the collection date and time.'), findsOneWidget);
      expect(submitted, isNull);

      // Pick a date and time (injectable picker supplied by the test), then
      // the request goes through carrying the full pickup contract.
      await tester.tap(find.byKey(const ValueKey('customer-pickup-schedule')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nov 15'), findsNWidgets(2));
      await reveal(tester, const ValueKey('customer-restrictions-check'));
      await tester.tap(
        find.byKey(const ValueKey('customer-restrictions-check')),
      );
      await reveal(tester, const ValueKey('customer-create-shipment'));
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(submitted?['deliveryMode'], 'PICKUP');
      expect(submitted?['pickupAddress'], '108 Dodge Street, Omaha');
      expect(submitted?['pickupScheduledAt'], DateTime(2026, 11, 15, 10, 30));
      expect(find.text('Request created.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('customer shipment form fits a compact screen with larger text', (
    tester,
  ) async {
    size(tester, const Size(320, 640), scale: 1.2);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith(_CustomerSession.new)],
        child: MaterialApp(
          theme: AppTheme.build(),
          home: Scaffold(
            body: CustomerShipmentScreen(
              loadParcels: () async => [],
              createParcel: ({
                required recipientName,
                required recipientPhone,
                required recipientAddress,
                required packageType,
                required weightKg,
                required origin,
                required destination,
                required method,
                required deliveryMode,
                restrictionsAcknowledged = false,
                pickupAddress,
                pickupScheduledAt,
                items = const [],
                notes,
                required clientRequestId,
              }) async => customerParcel,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('customer-create-shipment')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('customer-create-shipment')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
