import 'dart:io';
import 'dart:ui' as ui;

import 'package:d2f_application/core/theme.dart';
import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/providers/auth_provider.dart';
import 'package:d2f_application/screens/login_screen.dart';
import 'package:d2f_application/screens/signup_screen.dart';
import 'package:d2f_application/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuth extends AuthController {
  UserRole? registeredRole;
  String? registeredPhone;
  int registrations = 0;
  @override
  Future<User?> build() async => null;
  @override
  Future<User> signUp(
    String fullName,
    String email,
    String password, {
    String? phone,
    UserRole role = UserRole.CUSTOMER,
    String? invitation,
  }) async {
    registrations++;
    registeredRole = role;
    registeredPhone = phone;
    return User(id: 'test', fullName: fullName, email: email, role: role);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('PlusJakartaSans')
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  Widget wrap(
    Widget child, {
    FakeAuth? auth,
    double scale = 1,
    GlobalKey? boundary,
  }) => ProviderScope(
    overrides: [
      if (auth != null) authControllerProvider.overrideWith(() => auth),
    ],
    child: MaterialApp(
      theme: AppTheme.build(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RepaintBoundary(key: boundary, child: child),
    ),
  );
  void size(WidgetTester tester, Size value, {double keyboard = 0}) {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
  }

  for (final dimensions in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(430, 932),
  ]) {
    for (final keyboard in [0.0, 300.0]) {
      testWidgets('auth forms fit $dimensions with keyboard $keyboard', (
        tester,
      ) async {
        size(tester, dimensions, keyboard: keyboard);
        for (final screen in [
          const LoginScreen(),
          const SignupScreen(),
          if (keyboard == 0)
            SplashScreen(onSkip: () {}, onCreateAccount: () {}),
        ]) {
          await tester.pumpWidget(wrap(screen, scale: 1.2));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${screen.runtimeType}',
          );
          final pageScrolls = tester
              .widgetList<Scrollable>(find.byType(Scrollable))
              .where(
                (widget) =>
                    widget.axisDirection == AxisDirection.down ||
                    widget.axisDirection == AxisDirection.up,
              );
          // Text fields own horizontal scrolling; neither page scrolls vertically.
          expect(pageScrolls, isEmpty);
          if (screen is SignupScreen && keyboard == 0) {
            final art = tester.getRect(
              find.byKey(const ValueKey('signup-artwork')),
            );
            final title = tester.getRect(find.text('Join D2F'));
            expect(art.left, greaterThanOrEqualTo(title.right));
            expect(art.right, lessThanOrEqualTo(dimensions.width));
            expect(art.top, greaterThanOrEqualTo(0));
            expect(
              art.bottom,
              lessThan(
                tester.getTopLeft(find.byKey(const ValueKey('signup-name'))).dy,
              ),
            );
          }
          expect(
            find.text(screen is SignupScreen ? 'Create Account' : 'Sign In'),
            findsOneWidget,
          );
        }
      });
    }
  }

  testWidgets('signup text fields retain focus when tapped', (tester) async {
    size(tester, const Size(390, 844));
    await tester.pumpWidget(wrap(const SignupScreen()));
    await tester.pumpAndSettle();

    final nameField = find.descendant(
      of: find.byKey(const ValueKey('signup-name')),
      matching: find.byType(EditableText),
    );
    await tester.tap(nameField);
    await tester.pump();

    expect(tester.widget<EditableText>(nameField).focusNode.hasFocus, isTrue);
    expect(
      tester.testTextInput.log.map((call) => call.method),
      contains('TextInput.show'),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(nameField).focusNode.hasFocus,
      isTrue,
      reason: tester.testTextInput.log.map((call) => call.method).join(', '),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'swiping splash moves only artwork and retains both button bounds',
    (tester) async {
      size(tester, const Size(390, 844));
      var created = 0, signedIn = 0;
      await tester.pumpWidget(
        wrap(
          SplashScreen(
            onSkip: () => signedIn++,
            onCreateAccount: () => created++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final create = find.byKey(const ValueKey('splash-create-account'));
      final signIn = find.byKey(const ValueKey('splash-sign-in'));
      final createBounds = tester.getRect(create),
          signInBounds = tester.getRect(signIn);
      await tester.drag(find.byType(PageView), const Offset(-330, 0));
      await tester.pumpAndSettle();
      expect(tester.getRect(create), createBounds);
      expect(tester.getRect(signIn), signInBounds);
      expect(find.bySemanticsLabel('Background 2 of 3'), findsOneWidget);
      await tester.pump(const Duration(seconds: 15));
      expect(signedIn, 0);
      await tester.tap(create);
      await tester.tap(signIn);
      expect(created, 1);
      expect(signedIn, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'signup requires matching passwords then creates a customer without verification',
    (tester) async {
      size(tester, const Size(390, 844));
      final auth = FakeAuth();
      await tester.pumpWidget(wrap(const SignupScreen(), auth: auth));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('signup-name')),
        'Ama Mensah',
      );
      await tester.enterText(
        find.byKey(const ValueKey('signup-email')),
        'ama@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('signup-phone')),
        '90123456',
      );
      await tester.enterText(
        find.byKey(const ValueKey('signup-password')),
        'A-password-123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('signup-confirm-password')),
        'different',
      );
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      expect(
        find.text('Your passwords don’t match. Please check them.'),
        findsOneWidget,
      );
      expect(auth.registrations, 0);
      await tester.enterText(
        find.byKey(const ValueKey('signup-confirm-password')),
        'A-password-123',
      );
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      expect(auth.registrations, 1);
      expect(auth.registeredRole, UserRole.CUSTOMER);
      expect(auth.registeredPhone, '+22890123456');
      expect(find.text('6-digit code'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('driver signup asks for an invitation before registration', (
    tester,
  ) async {
    size(tester, const Size(390, 844));
    final auth = FakeAuth();
    await tester.pumpWidget(wrap(const SignupScreen(), auth: auth));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('signup-role-driver')));
    await tester.enterText(
      find.byKey(const ValueKey('signup-name')),
      'Driver Test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('signup-email')),
      'driver@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('signup-phone')),
      '90123456',
    );
    await tester.enterText(
      find.byKey(const ValueKey('signup-password')),
      'A-password-123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('signup-confirm-password')),
      'A-password-123',
    );
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    expect(find.text('Driver invitation'), findsOneWidget);
    expect(auth.registrations, 0);
    await tester.enterText(
      find.byKey(const ValueKey('signup-invitation')),
      'test-invitation',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(auth.registeredRole, UserRole.DRIVER);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'password toggles and country picker work without clearing fields',
    (tester) async {
      size(tester, const Size(390, 844));
      await tester.pumpWidget(wrap(const SignupScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('signup-password')),
        'Keep-this-123',
      );
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      final field = find.descendant(
        of: find.byKey(const ValueKey('signup-password')),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(field).obscureText, isFalse);
      expect(tester.widget<TextField>(field).controller!.text, 'Keep-this-123');
      await tester.tap(find.byTooltip('Country code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('United States  +1'));
      await tester.pumpAndSettle();
      expect(find.text('+1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('capture reference-sized auth screens for visual review', (
    tester,
  ) async {
    size(tester, const Size(390, 844));
    for (final entry in [
      ('01-splash', SplashScreen(onSkip: () {}, onCreateAccount: () {})),
      ('02-sign-in', const LoginScreen()),
      ('03-join-d2f', const SignupScreen()),
    ]) {
      final key = GlobalKey();
      await tester.pumpWidget(wrap(entry.$2, boundary: key));
      await tester.runAsync(() async {
        await Future.wait([
          for (final asset in [
            'auth_journey.jpg',
            'auth_air.jpg',
            'auth_join.jpg',
            'auth_reference_map.png',
            'signup_shipping.png',
          ])
            precacheImage(
              AssetImage('assets/images/$asset'),
              key.currentContext!,
            ),
        ]);
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final capture = await boundary.toImage(pixelRatio: 2);
        final bytes = await capture.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('design/verification-auth')
          ..createSync(recursive: true);
        File('${directory.path}/${entry.$1}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        capture.dispose();
      });
    }
  });
}
