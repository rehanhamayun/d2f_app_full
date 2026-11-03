import 'package:d2f_application/core/theme.dart';
import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/providers/auth_provider.dart';
import 'package:d2f_application/screens/role_workspace_screen.dart';
import 'package:d2f_application/widgets/d2f_navigation_bar.dart';
import 'package:d2f_application/widgets/service_experience.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session extends AuthController {
  final UserRole role;
  _Session(this.role);
  @override
  Future<User?> build() async => User(
    id: 'customer',
    email: 'customer@example.test',
    fullName: 'Alex Morgan',
    role: role,
  );
}

void main() {
  setUpAll(() async {
    for (final font in [
      ('PlusJakartaSans', 'assets/fonts/PlusJakartaSans.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  Widget wrap({
    UserRole role = UserRole.CUSTOMER,
    double scale = 1,
    Future<List<Parcel>> Function()? load,
  }) => ProviderScope(
    overrides: [authControllerProvider.overrideWith(() => _Session(role))],
    child: MaterialApp(
      theme: AppTheme.build(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RoleWorkspaceScreen(loadCustomerParcels: load ?? () async => []),
    ),
  );
  void viewport(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets(
    'customer shopping destinations keep navigation and profile access',
    (tester) async {
      viewport(tester, 390);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      for (final entry in [
        ('marketplace', D2FService.marketplace, 4),
        ('buy', D2FService.buy, 5),
      ]) {
        await tester.tap(find.byKey(ValueKey('nav-${entry.$1}')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<D2FNavigationBar>(find.byType(D2FNavigationBar))
              .selectedIndex,
          entry.$3,
        );
        expect(
          tester
              .widget<D2FServiceScreen>(find.byType(D2FServiceScreen))
              .service,
          entry.$2,
        );
        expect(find.byKey(const ValueKey('nav-home')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('header-profile')));
        await tester.pumpAndSettle();
        expect(find.text('Your profile'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('nav-home')));
        await tester.pumpAndSettle();
      }
      final bottom = tester.getRect(find.byType(D2FNavigationBar)).top;
      for (final service in D2FService.values.where((s) => !s.isComingSoon)) {
        final rect = tester.getRect(
          find.byKey(ValueKey('service-${service.name}')),
        );
        expect(
          rect.bottom,
          lessThanOrEqualTo(bottom),
          reason: '${service.name} should be visible without scrolling',
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'bell uses real shipment updates and supports retry without fake notifications',
    (tester) async {
      viewport(tester, 390);
      var calls = 0;
      final parcel = Parcel.fromJson({
        'id': 'update-1',
        'trackingId': 'D2F000000000001',
        'customerId': 'c1',
        'recipientName': 'Kossi',
        'packageType': 'BOX',
        'weightKg': 2,
        'origin': 'Omaha, NE, USA',
        'destination': 'Lomé, Togo',
        'method': 'SEA',
        'status': 'IN_TRANSIT',
        'createdAt': '2026-10-20T10:00:00Z',
        'updatedAt': '2026-10-29T11:00:00Z',
      });
      await tester.pumpWidget(
        wrap(
          load: () async {
            if (calls++ == 0) throw Exception('offline');
            return [parcel];
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('header-notifications')));
      await tester.pumpAndSettle();
      expect(find.text('Could not load shipment updates.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text(parcel.trackingId), findsOneWidget);
      expect(find.byKey(const ValueKey('update-update-1')), findsOneWidget);
      await tester.tap(find.byTooltip('Close updates'));
      await tester.pumpAndSettle();
      expect(find.text('Ship. Deliver. Connect.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final role in [UserRole.CUSTOMER, UserRole.DRIVER]) {
    testWidgets(
      '$role reference header fits a narrow phone with enlarged text',
      (tester) async {
        viewport(tester, 320);
        await tester.pumpWidget(wrap(role: role, scale: 1.3));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
