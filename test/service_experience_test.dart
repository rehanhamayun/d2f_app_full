import 'dart:io';
import 'dart:ui' as ui;

import 'package:d2f_application/core/theme.dart';
import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/providers/auth_provider.dart';
import 'package:d2f_application/screens/role_workspace_screen.dart';
import 'package:d2f_application/screens/connect_screen.dart';
import 'package:d2f_application/widgets/service_experience.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Customer extends AuthController {
  @override
  Future<User?> build() async => const User(
    id: 'customer',
    email: 'customer@example.test',
    fullName: 'Alex Morgan',
    role: UserRole.CUSTOMER,
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

  Widget wrap(Widget child, {double scale = 1, GlobalKey? boundary}) =>
      ProviderScope(
        overrides: [authControllerProvider.overrideWith(_Customer.new)],
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

  void viewport(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> capture(
    WidgetTester tester,
    GlobalKey boundary,
    String name,
  ) async {
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    await tester.pump();
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final folder = Directory('design/verification-services')
        ..createSync(recursive: true);
      File('${folder.path}/$name.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    });
    debugDisableShadows = previousShadows;
    await tester.pump();
  }

  testWidgets(
    'home opens each preview independently and returns to the service directory',
    (tester) async {
      viewport(tester, 390);
      await tester.pumpWidget(
        wrap(RoleWorkspaceScreen(loadCustomerParcels: () async => [])),
      );
      await tester.pumpAndSettle();
      for (final service in [
        D2FService.buy,
        D2FService.marketplace,
        D2FService.africa,
        D2FService.business,
        D2FService.loads,
        D2FService.local,
      ]) {
        final tile = find.byKey(ValueKey('service-${service.name}'));
        await reveal(tester, tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<D2FServiceScreen>(find.byType(D2FServiceScreen))
              .service,
          service,
        );
        expect(
          find
                  .textContaining('Coming soon', findRichText: true)
                  .evaluate()
                  .isNotEmpty ||
              find.textContaining('coming soon').evaluate().isNotEmpty,
          isTrue,
        );
        if (service == D2FService.buy || service == D2FService.marketplace) {
          await tester.tap(find.byKey(const ValueKey('nav-home')));
        } else {
          await tester.pageBack();
        }
        await tester.pumpAndSettle();
        expect(find.byType(RoleWorkspaceScreen), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shopping modes, category search, country selection and enquiry actions work',
    (tester) async {
      viewport(tester, 390);
      var enquiries = 0;
      await tester.pumpWidget(
        wrap(
          D2FServiceScreen(
            service: D2FService.buy,
            onContact: () => enquiries++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('buy-mode-1')));
      await tester.tap(find.byKey(const ValueKey('buy-mode-1')));
      await tester.pumpAndSettle();
      expect(find.text('Your shopping. One shipment.'), findsOneWidget);
      await reveal(tester, find.byKey(const ValueKey('service-contact')));
      await tester.tap(find.byKey(const ValueKey('service-contact')));
      expect(enquiries, 1);

      await tester.pumpWidget(
        wrap(
          const D2FServiceScreen(
            key: ValueKey('market'),
            service: D2FService.marketplace,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('marketplace-search')));
      await tester.enterText(
        find.byKey(const ValueKey('marketplace-search')),
        'beauty',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('market-category-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('market-category-1')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('market-category-4')));
      await tester.pumpAndSettle();
      expect(find.text('A little everyday care'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('marketplace-search')),
        'unknown',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('No matching categories'), findsOneWidget);

      await tester.pumpWidget(
        wrap(
          const D2FServiceScreen(
            key: ValueKey('africa'),
            service: D2FService.africa,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.byKey(const ValueKey('delivery-country-Ghana')),
      );
      await tester.tap(find.byKey(const ValueKey('delivery-country-Ghana')));
      await tester.pumpAndSettle();
      expect(find.text('Delivery enquiries · Ghana'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 600.0]) {
    testWidgets(
      'service screens fit ${width}dp with enlarged text through the entire page',
      (tester) async {
        viewport(tester, width);
        for (final service in D2FService.values.where(
          (s) => s != D2FService.shipping && s != D2FService.connect,
        )) {
          await tester.pumpWidget(
            wrap(
              D2FServiceScreen(key: ValueKey(service), service: service),
              scale: 1.3,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: service.name);
          await reveal(tester, find.byKey(const ValueKey('service-contact')));
          expect(tester.takeException(), isNull, reason: service.name);
        }
      },
    );
  }

  testWidgets('capture every service with bundled artwork for visual review', (
    tester,
  ) async {
    viewport(tester, 390);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      wrap(
        RoleWorkspaceScreen(loadCustomerParcels: () async => []),
        boundary: boundary,
      ),
    );
    await tester.runAsync(() async {
      for (final name in [
        'shipping',
        'buy',
        'marketplace',
        'connect',
        'delivery',
      ]) {
        await precacheImage(
          AssetImage('assets/images/services_$name.jpg'),
          boundary.currentContext!,
        );
      }
    });
    await tester.pumpAndSettle();
    await capture(tester, boundary, '01-home');
    await reveal(tester, find.byKey(const ValueKey('service-shipping')));
    await capture(tester, boundary, '01b-service-directory');
    for (final service in [
      D2FService.buy,
      D2FService.marketplace,
      D2FService.africa,
      D2FService.business,
      D2FService.loads,
    ]) {
      if (service == D2FService.buy || service == D2FService.marketplace) {
        await tester.pumpWidget(
          wrap(
            RoleWorkspaceScreen(loadCustomerParcels: () async => []),
            boundary: boundary,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            ValueKey(service == D2FService.buy ? 'nav-buy' : 'nav-marketplace'),
          ),
        );
      } else {
        await tester.pumpWidget(
          wrap(
            D2FServiceScreen(key: ValueKey(service), service: service),
            boundary: boundary,
          ),
        );
      }
      await tester.pumpAndSettle();
      await capture(tester, boundary, '02-${service.name}');
    }
    await tester.pumpWidget(
      wrap(
        ConnectScreen(
          request: (path, {method = 'GET', data}) async =>
              path == '/catalog' ? <String, dynamic>{} : <dynamic>[],
        ),
        boundary: boundary,
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, boundary, '04-connect');
    expect(tester.takeException(), isNull);
  });
}
