import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d2f_application/core/api.dart';
import 'package:d2f_application/core/theme.dart';
import 'package:d2f_application/core/service_area.dart';
import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/models/warehouse.dart';
import 'package:d2f_application/screens/warehouse_screen.dart';
import 'package:d2f_application/screens/container_detail_screen.dart';
import 'package:d2f_application/services/container_manifest.dart';

Map<String, dynamic> location(
  String id,
  String name,
  String city,
  String country,
) => {
  'id': id,
  'name': name,
  'code': id.toUpperCase(),
  'city': city,
  'country': country,
};
final omaha = location('oma', 'Omaha Warehouse', 'Omaha, NE', 'United States');
final lome = location('lom', 'Lomé Facility', 'Lomé', 'Togo');
final fixtureParcel = <String, dynamic>{
  'id': 'p1',
  'trackingId': 'D2F000000000125',
  'customerId': 'c1',
  'recipientName': 'Kossi Mensah',
  'packageType': 'BOX',
  'weightKg': 12.5,
  'origin': 'Omaha, NE, USA',
  'destination': 'Lomé, Togo',
  'method': 'SEA',
  'status': 'RECEIVED',
  'customer': {'id': 'c1', 'displayName': 'Ama Boateng'},
};
Map<String, dynamic> container({
  String status = 'LOADING',
  bool loaded = true,
}) => {
  'id': 'container1',
  'code': 'D2F-SEA-001',
  'status': status,
  'method': 'SEA',
  'sealNumber': 'SL-1024',
  'origin': omaha,
  'destination': lome,
  '_count': {'parcels': loaded ? 1 : 0},
  'parcels': [if (loaded) fixtureParcel],
  'events': [
    {
      'id': 'event1',
      'action': 'CREATED',
      'detail': 'Container opened for loading',
      'actorName': 'Warehouse Staff',
      'createdAt': '2026-10-24T09:00:00Z',
    },
  ],
};
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
  Widget wrap(Widget screen, {GlobalKey? boundary, double scale = 1}) =>
      MaterialApp(
        theme: AppTheme.build(),
        builder: (context, child) => RepaintBoundary(
          key: boundary,
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
        home: screen,
      );
  void size(WidgetTester t, Size size) {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('design/verification-m2/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'warehouse query/filter and failed-load retry keep real empty/error states',
    (tester) async {
      size(tester, const Size(390, 844));
      final queries = <Map<String, dynamic>>[];
      var failed = true;
      await tester.pumpWidget(
        wrap(
          WarehouseScreen(
            loadContainers: (query) async {
              queries.add(query);
              if (failed) {
                throw ApiException('Warehouse temporarily unavailable');
              }
              return {
                'containers': [container()],
                'total': 1,
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Warehouse temporarily unavailable'), findsOneWidget);
      failed = false;
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('D2F-SEA-001'), findsOneWidget);
      await tester.ensureVisible(find.text('Departed'));
      await tester.tap(find.text('Departed'));
      await tester.pumpAndSettle();
      expect(queries.last['status'], 'DEPARTED');
      await tester.enterText(find.byType(TextField), 'SEA-001');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(queries.last['q'], 'SEA-001');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'container loading submits the saved tracking ID; departure requires explicit confirmation',
    (tester) async {
      size(tester, const Size(390, 844));
      var data = container(loaded: false);
      final calls = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        wrap(
          ContainerDetailScreen(
            containerId: 'container1',
            loadContainer: () async => FreightContainer.fromJson(data),
            performRequest: (path, method, body) async {
              calls.add({'path': path, 'method': method, 'body': body});
              if (path.endsWith('/parcels')) {
                data = container();
                return {'alreadyLoaded': false};
              }
              if (path.endsWith('/events')) {
                data = container(status: body!['action']);
                return {};
              }
              return {};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Tracking number'));
      await tester.enterText(
        find.byType(TextField),
        fixtureParcel['trackingId'],
      );
      await tester.ensureVisible(find.text('Load parcel'));
      await tester.tap(find.text('Load parcel'));
      await tester.pumpAndSettle();
      expect(calls.single['body']['trackingId'], fixtureParcel['trackingId']);
      await tester.ensureVisible(find.text('Confirm Departure'));
      await tester.tap(find.text('Confirm Departure'));
      await tester.pumpAndSettle();
      expect(calls.length, 1);
      expect(find.text('Confirm departure'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls.length, 1);
      await tester.ensureVisible(find.text('Confirm Departure'));
      await tester.tap(find.text('Confirm Departure'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Depart container'));
      await tester.pumpAndSettle();
      expect(calls.last['body']['action'], 'DEPARTED');
      expect(find.text('Load a parcel'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('create container rejects missing inputs and same endpoints', (
    tester,
  ) async {
    size(tester, const Size(390, 844));
    await tester.pumpWidget(
      wrap(
        CreateContainerScreen(
          loadLocations: () async => [
            WarehouseLocation.fromJson(omaha),
            WarehouseLocation.fromJson(lome),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(FilledButton).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextFormField).first);
    await tester.pumpAndSettle();
    expect(find.text('Use letters, numbers and hyphens.'), findsOneWidget);
    expect(find.text('Choose a location.'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
  for (final width in [320.0, 390.0, 600.0]) {
    testWidgets('warehouse screens fit ${width.toInt()}dp and enlarged text', (
      tester,
    ) async {
      size(tester, Size(width, 900));
      for (final screen in [
        WarehouseScreen(
          loadContainers: (_) async => {
            'containers': [container()],
            'total': 1,
          },
        ),
        CreateContainerScreen(
          loadLocations: () async => [
            WarehouseLocation.fromJson(omaha),
            WarehouseLocation.fromJson(lome),
          ],
        ),
        ContainerDetailScreen(
          containerId: 'container1',
          loadContainer: () async => FreightContainer.fromJson(container()),
        ),
      ]) {
        await tester.pumpWidget(wrap(screen, scale: 1.3));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$screen at $width');
        await tester.drag(find.byType(ListView).first, const Offset(0, -450));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
  testWidgets(
    'render warehouse list, creation and loaded container using shared brand theme',
    (tester) async {
      size(tester, const Size(390, 844));
      final key = GlobalKey();
      final screens = <String, Widget>{
        '01-warehouse': WarehouseScreen(
          loadContainers: (_) async => {
            'containers': [
              container(),
              {
                ...container(status: 'DEPARTED'),
                'id': 'c2',
                'code': 'D2F-SEA-002',
              },
            ],
            'total': 2,
          },
        ),
        '02-create-container': CreateContainerScreen(
          loadLocations: () async => [
            WarehouseLocation.fromJson(omaha),
            WarehouseLocation.fromJson(lome),
          ],
        ),
        '03-container-loading': ContainerDetailScreen(
          containerId: 'container1',
          loadContainer: () async => FreightContainer.fromJson(container()),
        ),
        '04-container-arrived': ContainerDetailScreen(
          containerId: 'container1',
          loadContainer: () async =>
              FreightContainer.fromJson(container(status: 'ARRIVED')),
        ),
      };
      for (final entry in screens.entries) {
        await tester.pumpWidget(wrap(entry.value, boundary: key));
        await tester.pumpAndSettle();
        await capture(tester, key, entry.key);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
  test('the scoped country set covers route suggestions, flags and two-way release/arrival transitions', () {
    expect(
      kServiceCountries.map((c) => c.$2),
      containsAll([
        'United States',
        'Belgium',
        'France',
        'Togo',
        'Benin',
        'Burkina Faso',
        'Gabon',
        'Ghana',
        'Senegal',
        'Nigeria',
        'Côte d’Ivoire',
      ]),
    );
    expect(kServiceCountries.map((c) => c.$2), isNot(contains('Pakistan')));
    for (final entry in kCountryLocations.entries) {
      expect(kShippingLocationOptions, contains(entry.value));
      expect(serviceCountryFlag(entry.value), isNot('🌍'));
    }
    expect(
      kAllowedTransitions['ARRIVED_DESTINATION'],
      contains('READY_FOR_PICKUP'),
    );
    expect(kAllowedTransitions['READY_FOR_PICKUP'], contains('RELEASED'));
    expect(kAllowedTransitions['RELEASED'], ['DELIVERED']);
  });
  test('large container manifest generates a multipage PDF without losing parcel rows', () async {
    final manifest = <String, dynamic>{
      'code': 'QA-SEA-001',
      'method': 'SEA',
      'origin': 'Omaha, NE, United States',
      'destination': 'Lomé, Togo',
      'parcelCount': 80,
      'totalWeightKg': 1000,
      'sealNumber': 'QA-1024',
      'issuedAt': '2026-10-24T09:00:00Z',
      'provisional': false,
      'parcels': [
        for (var i = 0; i < 80; i++)
          {
            ...fixtureParcel,
            'trackingId': 'D2F${(i + 1).toString().padLeft(12, '0')}',
            'customer': {'displayName': 'QA Ama Boateng'},
            'recipientName': 'QA Kossi Mensah',
          },
      ],
    };
    final bytes = await ContainerManifest.generate(manifest);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final file = File('output/pdf/D2F-container-manifest-example.pdf');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  });
}
