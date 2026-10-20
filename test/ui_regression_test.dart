import 'package:d2f_application/main.dart';
import 'package:d2f_application/screens/splash_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:d2f_application/core/theme.dart';
import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/screens/home_screen.dart';
import 'package:d2f_application/screens/account_screen.dart';
import 'package:d2f_application/screens/staff_only_gate.dart';
import 'package:d2f_application/screens/login_screen.dart';
import 'package:d2f_application/screens/parcel_success_screen.dart';
import 'package:d2f_application/screens/update_status_screen.dart';
import 'package:d2f_application/widgets/common.dart';
import 'package:d2f_application/widgets/timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final parcel = Parcel.fromJson({
  'id': 'ui-fixture',
  'trackingId': 'D2F-2026-000125',
  'customerId': 'c1',
  'recipientName': 'Test Recipient',
  'packageType': 'BOX',
  'weightKg': 2.5,
  'origin': 'Omaha, NE, USA',
  'destination': 'Lomé, Togo',
  'method': 'SEA',
  'status': 'RECEIVED',
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('PlusJakartaSans');
    loader.addFont(rootBundle.load('assets/fonts/PlusJakartaSans.ttf'));
    await loader.load();
  });

  Widget wrap(Widget child, {double scale = 1}) => ProviderScope(
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

  testWidgets(
    'tracking search arrow submits the typed number without an external controller',
    (tester) async {
      String? submitted;
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: D2FSearchField(
              hint: 'Tracking number',
              onSubmit: (v) => submitted = v,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'D2F-2026-000125');
      await tester.tap(find.byTooltip('Search parcels'));
      expect(submitted, 'D2F-2026-000125');
    },
  );

  for (final size in [const Size(360, 800), const Size(412, 915)]) {
    testWidgets('M1 screens fit ${size.width.toInt()}dp with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final screens = <Widget>[
        Scaffold(
          body: HomeScreen(onGoRegister: () {}, onGoActivity: () {}),
        ),
        const LoginScreen(),
        const StaffOnlyGate(),
        const Scaffold(body: AccountScreen()),
        ParcelSuccessScreen(parcel: parcel),
        UpdateStatusScreen(parcel: parcel),
      ];
      for (final screen in screens) {
        await tester.pumpWidget(wrap(screen, scale: 1.2));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${screen.runtimeType} at $size',
        );
        if (screen is LoginScreen) {
          expect(
            find.byType(ListView),
            findsNothing,
            reason: 'Sign-in fits without a page scroll',
          );
        } else {
          final scrollable = find.byType(Scrollable).first;
          await tester.drag(scrollable, const Offset(0, -550));
          await tester.pumpAndSettle();
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'Scrolled ${screen.runtimeType} at $size',
        );
      }
    });
  }

  testWidgets('sign-in fits a compact screen while the keyboard is open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(const LoginScreen(), scale: 1.2));
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsNothing);
    expect(find.byKey(const ValueKey('staff-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('staff-password')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two splash stages transition smoothly into sign-in', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: D2FApp()));
    await tester.pump();
    await tester.runAsync(() async {
      final context = tester.element(find.byType(SplashScreen));
      await Future.wait([
        for (final asset in [
          'journey.jpg',
          'warehouse.jpg',
          'login.jpg',
          'd2f_2.png',
          'd2f_3.png',
        ])
          precacheImage(AssetImage('assets/images/$asset'), context),
      ]);
    });
    await tester.pump();
    expect(tester.widget<SplashScreen>(find.byType(SplashScreen)).stage, 0);
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 650));
    expect(tester.widget<SplashScreen>(find.byType(SplashScreen)).stage, 1);
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 650));
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'timeline shows recorded events and does not invent skipped stages',
    (tester) async {
      final event = TrackingEvent.fromJson({
        'id': 'e1',
        'status': 'IN_TRANSIT',
        'createdAt': '2026-10-20T06:00:00Z',
        'note': 'Departed Omaha',
        'location': 'Omaha warehouse - outbound staging area',
        'actor': {'fullName': 'Warehouse Staff'},
      });
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: TrackingTimeline(
              events: [event],
              currentStatus: 'IN_TRANSIT',
            ),
          ),
        ),
      );
      expect(find.text('Departed Omaha'), findsOneWidget);
      expect(find.text('By Warehouse Staff'), findsOneWidget);
      expect(find.text('Processing'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
