import 'dart:io';
import 'dart:ui' as ui;

import 'package:d2f_application/core/theme.dart';
import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/providers/auth_provider.dart';
import 'package:d2f_application/screens/connect_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session extends AuthController {
  @override
  Future<User?> build() async => const User(
    id: 'customer',
    email: 'customer@example.test',
    fullName: 'Mary Morgan',
    phone: '+12145550111',
    role: UserRole.CUSTOMER,
  );
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'PlusJakartaSans',
    )..addFont(rootBundle.load('assets/fonts/PlusJakartaSans.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      350,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 45,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Widget wrap(Widget child, GlobalKey boundary, {double scale = 1}) =>
      ProviderScope(
        overrides: [authControllerProvider.overrideWith(_Session.new)],
        child: MaterialApp(
          theme: AppTheme.build(),
          builder: (context, child) => RepaintBoundary(
            key: boundary,
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
          home: child,
        ),
      );
  Future<void> capture(
    WidgetTester tester,
    GlobalKey boundary,
    String name,
  ) async {
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('design/verification-connect')
        ..createSync(recursive: true);
      File('${directory.path}/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'Connect card fits narrow phones with enlarged text and opens its own service',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var opened = false;
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(18),
              child: ConnectServiceCard(onTap: () => opened = true),
            ),
          ),
          GlobalKey(),
          scale: 1.3,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('open-d2f-connect')));
      expect(opened, isTrue);
    },
  );
  testWidgets(
    'domestic booking requires declaration and preserves complete fields in the registered booking',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, dynamic>? submitted;
      Map<String, dynamic>? saved;
      Future<dynamic> api(
        String path, {
        String method = 'GET',
        Map<String, dynamic>? data,
      }) async {
        if (path == '/catalog') return {'trips': [], 'rates': []};
        if (path == '/trips' || path == '/bookings' && method == 'GET')
          return [];
        if (path == '/bookings' && method == 'POST') {
          submitted = data;
          saved = {
            ...data!,
            'id': 'booking',
            'internationalFeeMinor': null,
            'domesticCostMinor': null,
            'domesticStatus': 'AWAITING_ADMIN_REVIEW',
            'assignments': [],
            'receivingLocation': null,
            'parcel': {
              'id': 'parcel',
              'trackingId': 'D2F000000000101',
              'origin': data['origin'],
              'destination': data['destination'],
              'status': 'REQUESTED',
              'notes': data['description'],
              'weightKg': data['weightKg'],
              'recipientName': data['recipientName'],
              'recipientPhone': data['recipientPhone'],
              'recipientAddress': data['recipientAddress'],
              'events': [],
            },
          };
          return saved;
        }
        if (path == '/bookings/booking') return saved;
        throw StateError('Unexpected API call: $method $path');
      }

      final boundary = GlobalKey();
      await tester.pumpWidget(wrap(ConnectScreen(request: api), boundary));
      await tester.pumpAndSettle();
      await capture(tester, boundary, '01-connect-home');
      for (final entry in {
        'origin': 'New York, USA',
        'destination': 'Lomé, Togo',
        'description': 'Summer clothing in a sealed box',
        'weightKg': '5',
        'quantity': '1',
        'declaredValue': '200',
        'senderCity': 'Dallas, Texas',
        'recipientName': 'Kossi Morgan',
        'recipientPhone': '+22890001122',
        'recipientAddress': 'Lomé, Togo',
        'senderAddress': 'Private return address in Dallas',
      }.entries) {
        final field = find.byKey(ValueKey('connect-${entry.key}'));
        await reveal(tester, field);
        await tester.enterText(field, entry.value);
      }
      // Select the actual preferred travel date through the date picker.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 6000));
      await tester.pumpAndSettle();
      final dateButton = find.text('Earliest preferred travel date');
      await reveal(tester, dateButton);
      await tester.tap(dateButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('connect-submit-booking'));
      await reveal(tester, button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(submitted, isNull);
      expect(
        find.textContaining('Confirm your parcel declaration'),
        findsOneWidget,
      );
      final declaration = find.byKey(const ValueKey('connect-declaration'));
      await reveal(tester, declaration);
      expect(
        tester.getTopLeft(declaration).dy,
        lessThan(tester.getTopLeft(button).dy),
      );
      await tester.tap(declaration);
      await tester.pumpAndSettle();
      await capture(tester, boundary, '02-connect-declaration');
      await reveal(tester, button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(submitted?['handoverMode'], 'DOMESTIC_SHIPPING');
      expect(submitted?['senderCity'], 'Dallas, Texas');
      expect(submitted?['senderAddress'], 'Private return address in Dallas');
      expect(submitted?['declaredValueMinor'], 20000);
      expect(submitted?['weightKg'], 5);
      expect(submitted?['restrictionsAcknowledged'], isTrue);
      expect(submitted?['requestedTripId'], isNull);
      expect(find.text('D2F000000000101'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, boundary, '03-connect-booking');
    },
  );
  testWidgets(
    'Connect form and traveller registration fit compact screens with larger text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Future<dynamic> api(
        String path, {
        String method = 'GET',
        Map<String, dynamic>? data,
      }) async => path == '/catalog' ? {'trips': [], 'rates': []} : [];
      await tester.pumpWidget(
        wrap(ConnectScreen(request: api), GlobalKey(), scale: 1.3),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 12; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 10000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Travel & earn'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Register a trip'));
      await tester.tap(find.text('Register a trip'));
      await tester.pumpAndSettle();
      expect(find.text('Register your trip'), findsOneWidget);
      expect(find.textContaining('AWB'), findsNothing);
      for (var i = 0; i < 4; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
}
