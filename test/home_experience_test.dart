import 'dart:io';
import 'dart:ui' as ui;

import 'package:d2f_application/core/theme.dart';
import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/screens/home_screen.dart';
import 'package:d2f_application/screens/ship_screen.dart';
import 'package:d2f_application/screens/splash_screen.dart';
import 'package:d2f_application/widgets/d2f_navigation_bar.dart';
import 'package:d2f_application/widgets/route_planner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('PlusJakartaSans')
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await font.load();
    await icons.load();
    final cupertino = FontLoader('packages/cupertino_icons/CupertinoIcons')
      ..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      );
    await cupertino.load();
  });
  void viewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget wrap(Widget child, {double scale = 1, GlobalKey? appBoundary}) =>
      ProviderScope(
        child: RepaintBoundary(
          key: appBoundary,
          child: MaterialApp(
            theme: AppTheme.build(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: child,
          ),
        ),
      );

  for (final kind in [ui.PointerDeviceKind.touch, ui.PointerDeviceKind.mouse]) {
    testWidgets(
      'splash swipes from the headline in both directions with $kind',
      (tester) async {
        viewport(tester, const Size(390, 844));
        await tester.pumpWidget(
          wrap(SplashScreen(onSkip: () {}, onCreateAccount: () {})),
        );
        await tester.pumpAndSettle();
        final title = find.text('Bridging distances.\nBringing people closer.');
        final titleBounds = tester.getRect(title);
        final createBounds = tester.getRect(
          find.byKey(const ValueKey('splash-create-account')),
        );
        final signInBounds = tester.getRect(
          find.byKey(const ValueKey('splash-sign-in')),
        );
        for (final step in [
          (-280.0, 'Background 2 of 3'),
          (-280.0, 'Background 3 of 3'),
          (280.0, 'Background 2 of 3'),
          (280.0, 'Background 1 of 3'),
        ]) {
          final start = Offset(step.$1 < 0 ? 330 : 55, titleBounds.center.dy);
          final gesture = await tester.startGesture(start, kind: kind);
          await gesture.moveBy(Offset(step.$1, 0));
          await gesture.up();
          await tester.pumpAndSettle();
          final semantics = tester.getSemantics(find.bySemanticsLabel(step.$2));
          expect(semantics.flagsCollection.isSelected, ui.Tristate.isTrue);
          expect(tester.getRect(title), titleBounds);
          expect(
            tester.getRect(find.byKey(const ValueKey('splash-create-account'))),
            createBounds,
          );
          expect(
            tester.getRect(find.byKey(const ValueKey('splash-sign-in'))),
            signInBounds,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'route planner swaps direction, accepts typed cities and returns the selected shipping method',
    (tester) async {
      viewport(tester, const Size(390, 844));
      ShipmentRoute? chosen;
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: RoutePlannerCard(onRouteSelected: (route) => chosen = route),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('home-route-planner')));
      await tester.pumpAndSettle();
      expect(find.text('Choose your route'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('route-swap')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('route-origin')))
            .controller!
            .text,
        'Lomé, Togo',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('route-destination')),
            )
            .controller!
            .text,
        'Omaha, NE, USA',
      );
      await tester.enterText(
        find.byKey(const ValueKey('route-origin')),
        'Dakar, Senegal',
      );
      await tester.enterText(
        find.byKey(const ValueKey('route-destination')),
        'Paris, France',
      );
      await tester.tap(find.byKey(const ValueKey('route-method-sea')));
      await tester.tap(find.byKey(const ValueKey('route-use')));
      await tester.pumpAndSettle();
      expect(chosen?.origin, 'Dakar, Senegal');
      expect(chosen?.destination, 'Paris, France');
      expect(chosen?.method, ShippingMethod.SEA);
      expect(find.text('Dakar'), findsOneWidget);
      expect(find.text('Paris'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('route planner refuses empty and identical locations', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    var submitted = false;
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: RoutePlannerCard(onRouteSelected: (_) => submitted = true),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('home-route-planner')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('route-origin')), '');
    await tester.tap(find.byKey(const ValueKey('route-use')));
    await tester.pumpAndSettle();
    expect(submitted, isFalse);
    expect(
      find.text('Enter a city and country (3–120 characters).'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('route-origin')),
      'Lomé, Togo',
    );
    await tester.tap(find.byKey(const ValueKey('route-use')));
    await tester.pumpAndSettle();
    expect(
      find.text('Origin and destination must be different.'),
      findsOneWidget,
    );
    expect(submitted, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'chosen reverse routes and custom cities populate real parcel fields and update on subsequent selections',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final key = GlobalKey<ShipScreenState>();
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: ShipScreen(
              key: key,
              initialRoute: const ShipmentRoute(
                origin: 'Dakar, Senegal',
                destination: 'Paris, France',
                method: ShippingMethod.SEA,
              ),
              loadCustomers: () async => [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('parcel-origin-Dakar, Senegal')),
            )
            .initialValue,
        'Dakar, Senegal',
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('parcel-destination-Paris, France')),
            )
            .initialValue,
        'Paris, France',
      );
      key.currentState!.presetRoute(
        const ShipmentRoute(
          origin: 'Accra, Ghana',
          destination: 'New York, NY, USA',
          method: ShippingMethod.AIR,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('parcel-origin-Accra, Ghana')),
            )
            .initialValue,
        'Accra, Ghana',
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(
                const ValueKey('parcel-destination-New York, NY, USA'),
              ),
            )
            .initialValue,
        'New York, NY, USA',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(1280, 900),
  ]) {
    testWidgets('navigation fits $size and exposes all tabs', (tester) async {
      viewport(tester, size);
      var selected = 0;
      await tester.pumpWidget(
        wrap(
          StatefulBuilder(
            builder: (context, update) => Scaffold(
              bottomNavigationBar: D2FNavigationBar(
                selectedIndex: selected,
                onSelected: (index) => update(() => selected = index),
              ),
            ),
          ),
          scale: 1.3,
        ),
      );
      for (final entry in [
        ('ship', 1),
        ('activity', 2),
        ('profile', 3),
        ('home', 0),
      ]) {
        await tester.tap(find.byKey(ValueKey('nav-${entry.$1}')));
        await tester.pumpAndSettle();
        expect(selected, entry.$2);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'capture home cards, navigation and route planner for visual review',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final boundaryKey = GlobalKey();
      final appBoundaryKey = GlobalKey();
      await tester.pumpWidget(
        wrap(
          appBoundary: appBoundaryKey,
          RepaintBoundary(
            key: boundaryKey,
            child: Scaffold(
              body: HomeScreen(
                onGoRegister: () {},
                onGoActivity: () {},
                onGoRoute: (_) {},
              ),
              bottomNavigationBar: D2FNavigationBar(
                selectedIndex: 0,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future.wait([
          for (final file in [
            'home_register_hero.jpg',
            'home_track_hero.jpg',
            'home_parcels_hero.jpg',
            'warehouse.jpg',
            'd2f_2.png',
          ])
            precacheImage(
              AssetImage('assets/images/$file'),
              boundaryKey.currentContext!,
            ),
        ]);
      });
      await tester.pumpAndSettle();
      Future<void> capture(String name, RenderRepaintBoundary boundary) async {
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final folder = Directory('design/verification-home-refresh')
            ..createSync(recursive: true);
          File('${folder.path}/$name.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture(
        '01-home',
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-route-planner')),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await capture(
        '02-route-card',
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary,
      );
      await tester.tap(find.byKey(const ValueKey('home-route-planner')));
      await tester.pumpAndSettle();
      // A modal is on the navigator overlay, outside the home-page boundary.
      await capture(
        '03-route-planner',
        appBoundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
