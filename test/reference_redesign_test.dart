import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:d2f_application/core/api.dart';
import 'package:d2f_application/core/theme.dart';
import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/providers/auth_provider.dart';
import 'package:d2f_application/screens/home_screen.dart';
import 'package:d2f_application/screens/activity_screen.dart';
import 'package:d2f_application/screens/login_screen.dart';
import 'package:d2f_application/screens/signup_screen.dart';
import 'package:d2f_application/screens/splash_screen.dart';
import 'package:d2f_application/screens/role_workspace_screen.dart';
import 'package:d2f_application/screens/parcel_detail_screen.dart';
import 'package:d2f_application/screens/parcel_success_screen.dart';
import 'package:d2f_application/screens/update_status_screen.dart';
import 'package:d2f_application/screens/account_screen.dart';
import 'package:d2f_application/screens/ship_screen.dart';
import 'package:d2f_application/screens/customer_shipment_screen.dart';
import 'package:d2f_application/widgets/d2f_navigation_bar.dart';
import 'package:d2f_application/widgets/reference_widgets.dart';
import 'package:d2f_application/widgets/customer_profile_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Fixtures are confined to tests. Production screens use the existing API.
User testUser(UserRole role) => User(
  id: 'visual-user',
  email: 'alex@example.test',
  fullName: 'Alex Morgan',
  role: role,
  locationName: 'Omaha Warehouse',
  organizationName: 'D2F Shipping',
);

class _Session extends AuthController {
  final UserRole role;
  _Session(this.role);
  @override
  Future<User?> build() async => testUser(role);
}

final parcel = Parcel.fromJson({
  'id': 'test-parcel-id',
  'trackingId': 'D2F-2026-000125',
  'customerId': 'test-customer',
  'recipientName': 'Test Recipient',
  'recipientPhone': '+228 90000000',
  'recipientAddress': 'Test address',
  'packageType': 'BOX',
  'weightKg': 2.5,
  'origin': 'Omaha, NE, USA',
  'destination': 'Lomé, Togo',
  'method': 'AIR',
  'status': 'IN_TRANSIT',
  'createdAt': '2026-10-18T09:00:00Z',
  'updatedAt': '2026-10-21T10:00:00Z',
  'customer': {
    'id': 'test-customer',
    'displayName': 'Test Sender',
    'email': 'sender@example.test',
  },
  'events': [
    {
      'id': 'first',
      'status': 'RECEIVED',
      'createdAt': '2026-10-18T09:00:00Z',
      'location': 'Omaha Warehouse',
      'actor': {'fullName': 'Alex Morgan'},
    },
    {
      'id': 'current',
      'status': 'IN_TRANSIT',
      'createdAt': '2026-10-21T10:00:00Z',
      'note': 'Departed origin facility',
      'location': 'Omaha, USA',
    },
  ],
});
const counts = {
  'RECEIVED': 7,
  'PROCESSING': 3,
  'IN_TRANSIT': 12,
  'DELIVERED': 5,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in [
      ('PlusJakartaSans', 'assets/fonts/PlusJakartaSans.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/cupertino_icons/CupertinoIcons',
        'packages/cupertino_icons/assets/CupertinoIcons.ttf',
      ),
    ]) {
      await (FontLoader(entry.$1)..addFont(rootBundle.load(entry.$2))).load();
    }
  });
  void viewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget wrap(
    Widget child, {
    UserRole role = UserRole.STAFF,
    double scale = 1,
    GlobalKey? boundary,
  }) => ProviderScope(
    overrides: [authControllerProvider.overrideWith(() => _Session(role))],
    child: MaterialApp(
      theme: AppTheme.build(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(key: boundary, child: child!),
      ),
      home: child,
    ),
  );
  HomeScreen home({VoidCallback? onShip, VoidCallback? onActivity}) =>
      HomeScreen(
        loadStats: () async => counts,
        loadRecent: () async => [parcel],
        onGoRegister: onShip ?? () {},
        onGoActivity: onActivity ?? () {},
      );

  testWidgets(
    'dashboard uses loaded counts, real user metadata, and preserved actions',
    (tester) async {
      viewport(tester, const Size(390, 844));
      var ship = 0, activity = 0;
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: home(onShip: () => ship++, onActivity: () => activity++),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final metrics = tester
          .widgetList<DashboardMetric>(find.byType(DashboardMetric))
          .toList();
      expect(metrics.map((m) => m.value), ['27', '12', '3', '5']);
      expect(find.textContaining('Alex'), findsOneWidget);
      expect(find.text('Assigned location: Omaha Warehouse'), findsOneWidget);
      await tester.tap(find.text('Register\nParcel'));
      await tester.pump();
      expect(ship, 1);
      await tester.tap(find.text('Total Parcels'));
      await tester.pump();
      expect(activity, 1);
      await tester.scrollUntilVisible(
        find.text(parcel.trackingId),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(parcel.trackingId), findsOneWidget);
      expect(find.text('Daniel'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dashboard does not manufacture counts during loading or failures and can retry',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final loading = Completer<Map<String, int>>();
      var attempts = 0;
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: HomeScreen(
              onGoRegister: () {},
              onGoActivity: () {},
              loadStats: () =>
                  attempts++ == 0 ? loading.future : Future.value(counts),
              loadRecent: () async => [],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widgetList<DashboardMetric>(find.byType(DashboardMetric))
            .every((m) => m.value == '—'),
        isTrue,
      );
      loading.completeError(ApiException('Offline'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(
        tester
            .widgetList<DashboardMetric>(find.byType(DashboardMetric))
            .every((m) => m.value == '—'),
        isTrue,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DashboardMetric>(find.byType(DashboardMetric).first)
            .value,
        '27',
      );
      expect(find.text('Retry'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('staff and admin action cards match the customer home layout', (
    tester,
  ) async {
    for (final role in [UserRole.STAFF, UserRole.ADMIN]) {
      viewport(tester, const Size(390, 844));
      await tester.pumpWidget(wrap(Scaffold(body: home()), role: role));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Scan Parcel'),
        180,
        scrollable: find.byType(Scrollable).first,
      );

      final cards = find.byType(ReferenceActionCard);
      expect(cards, findsNWidgets(3));
      final register = tester.getSize(cards.at(0));
      final scan = tester.getSize(cards.at(1));
      final search = tester.getSize(cards.at(2));
      expect(register.height, 184);
      expect(scan.height, 86);
      expect(search.height, 86);
      expect(register.width, greaterThan(scan.width));
      expect(scan.width, search.width);
      expect(find.text('Register\nParcel'), findsOneWidget);
      expect(find.text('Scan Parcel'), findsOneWidget);
      expect(find.text('Search Parcel'), findsOneWidget);
      expect(find.text('Create a shipment'), findsOneWidget);
      expect(find.text('Scan a QR or barcode'), findsOneWidget);
      expect(find.text('Find any shipment'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'customer home follows the reference hierarchy and shipping methods prefill a shipment request',
    (tester) async {
      viewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        wrap(const RoleWorkspaceScreen(), role: UserRole.CUSTOMER),
      );
      await tester.pumpAndSettle();

      expect(find.text('Good things.\nGoing places.'), findsOneWidget);
      expect(find.text('Send\nPackage'), findsOneWidget);
      expect(find.text('Track Parcel'), findsOneWidget);
      expect(find.text('Buy For Me'), findsOneWidget);
      expect(find.text('Enter tracking number'), findsOneWidget);
      expect(find.text('How would you like to send?'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Explore more'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Recharge & Data'), findsOneWidget);
      expect(find.text('Partner Offers'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-method-sea')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('home-method-sea')));
      await tester.pumpAndSettle();
      expect(find.text('Sea · Cost-effective'), findsOneWidget);
      expect(find.byType(CustomerShipmentScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('customer-create-shipment')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('customer destination chips prefill the shipment request', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      wrap(const RoleWorkspaceScreen(), role: UserRole.CUSTOMER),
    );
    await tester.pumpAndSettle();
    final destination = find.byKey(const ValueKey('home-destination-togo'));
    await tester.scrollUntilVisible(
      destination,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(destination);
    await tester.pumpAndSettle();
    await tester.tap(destination);
    await tester.pumpAndSettle();

    expect(find.text('Lomé, Togo'), findsOneWidget);
    expect(find.byType(CustomerShipmentScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('customer-create-shipment')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final role in [UserRole.CUSTOMER, UserRole.DRIVER]) {
    for (final width in [320.0, 390.0, 600.0]) {
      testWidgets(
        '$role workspace navigation fits ${width}dp with larger text and retains role access',
        (tester) async {
          viewport(tester, Size(width, 844));
          await tester.pumpWidget(
            wrap(const RoleWorkspaceScreen(), role: role, scale: 1.3),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -620),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final key in ['ship', 'activity', 'profile', 'home']) {
            await tester.tap(find.byKey(ValueKey('nav-$key')));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          expect(find.byType(ShipScreen), findsNothing);
          expect(find.byType(HomeScreen), findsNothing);
          await tester.tap(find.byKey(const ValueKey('nav-activity')));
          await tester.pumpAndSettle();
          expect(find.text('Track Shipment'), findsOneWidget);
          expect(find.text('Update Status'), findsNothing);
        },
      );
    }
  }

  for (final width in [320.0, 390.0, 600.0]) {
    testWidgets(
      'parcel tabs and status action retain full records at ${width}dp',
      (tester) async {
        viewport(tester, Size(width, 844));
        await tester.pumpWidget(
          wrap(
            ParcelDetailScreen(
              parcelId: parcel.id,
              loadParcel: (_) async => parcel,
            ),
            scale: 1.3,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Tracking'));
        await tester.pumpAndSettle();
        expect(find.text('Received'), findsOneWidget);
        expect(find.text('Processing'), findsNothing);
        await tester.scrollUntilVisible(
          find.text('Download parcel details'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.dragUntilVisible(
          find.text('Details'),
          find.byType(Scrollable).first,
          const Offset(0, 500),
        );
        await tester.tap(find.text('Details'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('sender@example.test'),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('sender@example.test'), findsOneWidget);
        await tester.dragUntilVisible(
          find.text('Overview'),
          find.byType(Scrollable).first,
          const Offset(0, 500),
        );
        await tester.tap(find.text('Overview'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Update Status'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Update Status'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Update Status'));
        await tester.pumpAndSettle();
        expect(find.byType(UpdateStatusScreen), findsOneWidget);
        expect(find.text('Arrived in Lomé'), findsOneWidget);
        expect(find.text('Ready for Pickup'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'shipment activity retains status filters and sends the typed search query',
    (tester) async {
      viewport(tester, const Size(320, 844));
      String? query;
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: ActivityScreen(
              loadParcels: ({String? q}) async {
                query = q;
                return [parcel];
              },
              loadStats: () async => counts,
            ),
          ),
          scale: 1.3,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(parcel.trackingId), findsOneWidget);
      final chipScroll = find.descendant(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is ListView && widget.scrollDirection == Axis.horizontal,
        ),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Received (7)'),
        100,
        scrollable: chipScroll,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Received (7)'));
      await tester.pumpAndSettle();
      expect(find.text(parcel.trackingId), findsNothing);
      await tester.scrollUntilVisible(
        find.text('All (27)'),
        -100,
        scrollable: chipScroll,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('All (27)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), parcel.trackingId);
      await tester.tap(find.byTooltip('Search parcels'));
      await tester.pumpAndSettle();
      expect(query, parcel.trackingId);
      expect(find.text(parcel.trackingId), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'public tracking renders only redacted response and has no staff actions',
    (tester) async {
      viewport(tester, const Size(320, 844));
      await tester.pumpWidget(
        wrap(
          const PublicTrackingScreen(
            shipment: {
              'trackingId': 'D2F-2026-000125',
              'status': 'IN_TRANSIT',
              'method': 'AIR',
              'events': [
                {'status': 'RECEIVED', 'createdAt': '2026-10-18T09:00:00Z'},
                {'status': 'IN_TRANSIT', 'createdAt': '2026-10-21T10:00:00Z'},
              ],
            },
          ),
          role: UserRole.CUSTOMER,
          scale: 1.3,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Received'), findsOneWidget);
      expect(find.text('Update Status'), findsNothing);
      expect(find.text('Shipping label'), findsNothing);
      expect(find.text('Test Sender'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'render the reference redesign and secondary screens for visual review',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final shots = <(String, Widget, UserRole)>[
        (
          '01-splash',
          SplashScreen(onSkip: () {}, onCreateAccount: () {}),
          UserRole.CUSTOMER,
        ),
        ('02-login', const LoginScreen(), UserRole.CUSTOMER),
        ('03-signup', const SignupScreen(), UserRole.CUSTOMER),
        (
          '04-staff',
          Scaffold(
            body: home(),
            bottomNavigationBar: D2FNavigationBar(
              selectedIndex: 0,
              onSelected: (_) {},
            ),
          ),
          UserRole.STAFF,
        ),
        (
          '05-admin',
          Scaffold(
            body: home(),
            bottomNavigationBar: D2FNavigationBar(
              selectedIndex: 0,
              onSelected: (_) {},
            ),
          ),
          UserRole.ADMIN,
        ),
        ('06-customer', const RoleWorkspaceScreen(), UserRole.CUSTOMER),
        ('07-driver', const RoleWorkspaceScreen(), UserRole.DRIVER),
        (
          '08-parcel',
          ParcelDetailScreen(
            parcelId: parcel.id,
            loadParcel: (_) async => parcel,
          ),
          UserRole.STAFF,
        ),
        (
          '09-booking',
          Scaffold(body: ShipScreen(loadCustomers: () async => [])),
          UserRole.STAFF,
        ),
        ('10-account', const Scaffold(body: AccountScreen()), UserRole.STAFF),
        ('11-success', ParcelSuccessScreen(parcel: parcel), UserRole.STAFF),
        ('12-update', UpdateStatusScreen(parcel: parcel), UserRole.STAFF),
        (
          '13-activity',
          Scaffold(
            body: ActivityScreen(
              loadParcels: ({String? q}) async => [parcel],
              loadStats: () async => counts,
            ),
          ),
          UserRole.STAFF,
        ),
      ];
      for (final shot in shots) {
        await tester.pumpWidget(const SizedBox.shrink());
        final key = GlobalKey();
        await tester.pumpWidget(wrap(shot.$2, role: shot.$3, boundary: key));
        await tester.runAsync(() async {
          await Future.wait([
            for (final asset in [
              'journey.jpg',
              'login.jpg',
              'parcel.jpg',
              'warehouse.jpg',
              'success.jpg',
              'tracking_globe_reference.png',
              'send_parcel_reference.png',
            ])
              precacheImage(
                AssetImage('assets/images/$asset'),
                key.currentContext!,
              ),
          ]);
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: shot.$1);
        if (shot.$1 == '08-parcel') {
          await tester.tap(find.text('Tracking'));
          await tester.pumpAndSettle();
        }
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('design/verification-reference-redesign')
            ..createSync(recursive: true);
          File('${directory.path}/${shot.$1}.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );

  testWidgets(
    'capture the customer ship, route, track, tracking detail and account screens',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final key = GlobalKey();
      final directory = Directory('design/verification-customer')
        ..createSync(recursive: true);

      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('${directory.path}/$name.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpWidget(
        wrap(
          const RoleWorkspaceScreen(),
          role: UserRole.CUSTOMER,
          boundary: key,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-ship')));
      await capture('01-customer-ship');
      expect(find.text('Your next shipment'), findsOneWidget);
      expect(find.byKey(const ValueKey('customer-route')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('customer-route')));
      await capture('02-customer-route-planner');
      expect(find.text('Choose your route'), findsOneWidget);
      expect(find.byKey(const ValueKey('route-use')), findsOneWidget);
      await tester.tap(find.byTooltip('Close route planner'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('nav-activity')));
      await capture('03-customer-track');
      expect(find.text('Track a shipment'), findsOneWidget);
      expect(find.text('Update Status'), findsNothing);
      expect(find.text('D2F-2026-000123'), findsOneWidget);

      await tester.pumpWidget(
        wrap(
          const PublicTrackingScreen(
            shipment: {
              'trackingId': 'D2F-2026-000125',
              'status': 'IN_TRANSIT',
              'method': 'AIR',
              'events': [
                {'status': 'RECEIVED', 'createdAt': '2026-10-18T09:00:00Z'},
                {'status': 'IN_TRANSIT', 'createdAt': '2026-10-21T10:00:00Z'},
              ],
            },
          ),
          role: UserRole.CUSTOMER,
          boundary: key,
        ),
      );
      await capture('04-customer-tracking-details');
      expect(find.text('D2F-2026-000125'), findsOneWidget);
      expect(find.text('Update Status'), findsNothing);

      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: CustomerProfileView(
              user: testUser(UserRole.CUSTOMER),
              connected: true,
              onEdit: () {},
              onSupport: () {},
              onSignOut: () {},
              onCheckConnection: () {},
              onTrack: () {},
              onShip: () {},
            ),
          ),
          role: UserRole.CUSTOMER,
          boundary: key,
        ),
      );
      await capture('05-customer-account');
      expect(find.text('CUSTOMER'), findsOneWidget);
      expect(find.text('Your shipping tools'), findsOneWidget);
    },
  );
}
