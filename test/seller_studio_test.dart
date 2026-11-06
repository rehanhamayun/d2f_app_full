import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:d2f_application/core/api.dart';
import 'package:d2f_application/core/theme.dart';
import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/providers/auth_provider.dart';
import 'package:d2f_application/screens/marketplace/seller_studio_screen.dart';
import 'package:d2f_application/screens/marketplace/buy_for_me_shop.dart';
import 'package:d2f_application/screens/marketplace/ship_for_me_shop.dart';
import 'package:d2f_application/screens/marketplace/seller_orders_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _customer = User(
  id: 'seller',
  email: 'seller@example.test',
  fullName: 'Seller',
  role: UserRole.CUSTOMER,
);

class _Session extends AuthController {
  final Future<User?> session;
  _Session(this.session);
  @override
  Future<User?> build() => session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides? previousOverrides;
  late HttpServer server;
  final calls = <String, int>{};
  var status = 'APPROVED';
  var failProfile = false;
  var hasProfile = true;
  final profile = <String, dynamic>{
    'id': 'seller-profile',
    'displayName': 'Adjoa Store',
    'businessType': 'INDIVIDUAL',
    'category': 'Home',
    'phone': '+22890000000',
    'country': 'Togo',
    'city': 'Lomé',
    'commissionBps': 1000,
  };

  setUpAll(() async {
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    FlutterSecureStorage.setMockInitialValues({});
    await Api.I.init();
  });
  tearDownAll(() {
    HttpOverrides.global = previousOverrides;
  });
  setUp(() async {
    calls.clear();
    status = 'APPROVED';
    failProfile = false;
    hasProfile = true;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      calls.update(path, (count) => count + 1, ifAbsent: () => 1);
      Object response = [];
      if (path == '/seller/me') {
        if (failProfile) {
          request.response.statusCode = 503;
          response = {'error': 'Temporary outage'};
        } else {
          response = {
            'profile': hasProfile ? {...profile, 'status': status} : null,
            'productCount': 0,
            'openOrders': 0,
          };
        }
      } else if (path == '/ship-for-me/warehouse-address' ||
          path == '/ship-for-me/terms') {
        request.response.statusCode = 404;
        response = {'error': 'Not configured'};
      }
      request.response.persistentConnection = false;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    await Api.I.setBaseUrl('http://127.0.0.1:${server.port}');
  });
  tearDown(() async {
    await server.close(force: true);
    await Api.I.setBaseUrl('');
  });

  Widget wrap(Widget child, {Future<User?>? session, double scale = 1}) =>
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => _Session(session ?? Future.value(_customer)),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.build(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: child,
        ),
      );
  // Flush real loopback HTTP as well as Flutter frames. Requests stay observable
  // so a refresh/remount feedback loop fails the request-count assertions.
  Future<void> settleNetwork(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'approved studio waits for auth, loads once and preserves Orders during refresh',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = Completer<User?>();
      await tester.pumpWidget(
        wrap(const SellerStudioScreen(), session: session.future),
      );
      await tester.pump();
      expect(calls, isEmpty);
      session.complete(_customer);
      await settleNetwork(tester);
      expect(find.text('Adjoa Store'), findsOneWidget);
      expect(find.text('New listing'), findsOneWidget);
      expect(calls['/seller/me'], 1);
      expect(calls['/seller/products'], 1);
      await tester.tap(find.text('Orders'));
      await settleNetwork(tester);
      expect(find.text('No new requests'), findsOneWidget);
      expect(calls['/seller/orders'], 1);
      final ordersState = tester.state(find.byType(SellerOrdersTab));
      await tester.tap(find.byTooltip('Refresh'));
      await settleNetwork(tester);
      expect(tester.state(find.byType(SellerOrdersTab)), same(ordersState));
      expect(find.text('No new requests'), findsOneWidget);
      expect(calls['/seller/me'], 2);
      expect(calls['/seller/products'], 1);
      expect(calls['/seller/orders'], 1);
      await tester.pump(const Duration(seconds: 3));
      await settleNetwork(tester);
      expect(calls['/seller/me'], 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'admin approval unlocks listings on refresh; narrow enlarged studio scrolls',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      status = 'PENDING';
      await tester.pumpWidget(wrap(const SellerStudioScreen(), scale: 1.3));
      await settleNetwork(tester);
      expect(find.text('Application under review'), findsOneWidget);
      expect(calls['/seller/products'], isNull);
      status = 'APPROVED';
      await tester.tap(find.byTooltip('Refresh'));
      await settleNetwork(tester);
      await tester.drag(find.byType(NestedScrollView), const Offset(0, -450));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Orders'));
      await tester.tap(find.text('Orders'));
      await settleNetwork(tester);
      expect(find.text('No new requests'), findsOneWidget);
      expect(calls['/seller/me'], 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'outage offers explicit retry and a failed refresh keeps the shop',
    (tester) async {
      failProfile = true;
      await tester.pumpWidget(wrap(const SellerStudioScreen()));
      await settleNetwork(tester);
      expect(find.text('Seller Studio could not be loaded.'), findsOneWidget);
      expect(calls['/seller/me'], 1);
      failProfile = false;
      await tester.tap(find.text('Try again'));
      await settleNetwork(tester);
      expect(find.text('Adjoa Store'), findsOneWidget);
      failProfile = true;
      await tester.tap(find.byTooltip('Refresh'));
      await settleNetwork(tester);
      expect(find.text('Adjoa Store'), findsOneWidget);
      expect(
        find.textContaining('Could not refresh your shop'),
        findsOneWidget,
      );
      expect(calls['/seller/me'], 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('new seller has a navigable application entry', (tester) async {
    hasProfile = false;
    await tester.pumpWidget(wrap(const SellerStudioScreen()));
    await settleNetwork(tester);
    expect(find.text('Sell on D2F'), findsOneWidget);
    await tester.ensureVisible(find.text('Apply to sell'));
    await tester.tap(find.text('Apply to sell'));
    await tester.pumpAndSettle();
    expect(find.text('Become a seller'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Sell on D2F'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final entry in [
    (const BuyForMeShop(), '/buy-for-me/requests'),
    (const ShipForMeShop(), '/ship-for-me/requests'),
  ]) {
    testWidgets('${entry.$2} starts once when the session becomes ready', (
      tester,
    ) async {
      final session = Completer<User?>();
      await tester.pumpWidget(
        wrap(Scaffold(body: entry.$1), session: session.future),
      );
      await tester.pump();
      expect(calls[entry.$2], isNull);
      session.complete(_customer);
      await settleNetwork(tester);
      expect(calls[entry.$2], 1);
      await tester.pump(const Duration(seconds: 3));
      await settleNetwork(tester);
      expect(calls[entry.$2], 1);
      expect(tester.takeException(), isNull);
    });
  }
}
