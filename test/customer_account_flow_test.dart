import 'package:d2f_application/core/api.dart';
import 'package:d2f_application/main.dart';
import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/providers/auth_provider.dart';
import 'package:d2f_application/screens/login_screen.dart';
import 'package:d2f_application/screens/role_workspace_screen.dart';
import 'package:d2f_application/screens/signup_screen.dart';
import 'package:d2f_application/screens/staff_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// A controlled session boundary for UI navigation. Real registration, login,
/// persistence and permission contracts are separately exercised in backend/test.
class _CustomerSession extends AuthController {
  User? saved;
  bool? remember;
  bool failSave = false;
  int updates = 0;
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
    saved = User(
      id: 'test-customer',
      email: email,
      fullName: fullName,
      role: role,
      phone: phone,
    );
    state = AsyncData(saved);
    return saved!;
  }

  @override
  Future<User> signIn(
    String email,
    String password, {
    bool remember = true,
  }) async {
    if (email != saved?.email || password != 'Customer-password-123') {
      throw ApiException('Invalid email or password.');
    }
    this.remember = remember;
    state = AsyncData(saved);
    return saved!;
  }

  @override
  Future<void> updateProfile(String name, String? phone) async {
    if (failSave) throw ApiException('Offline');
    updates++;
    saved = User(
      id: saved!.id,
      email: saved!.email,
      fullName: name,
      role: saved!.role,
      phone: phone,
    );
    state = AsyncData(saved);
  }

  @override
  Future<void> signOut() async {
    state = const AsyncData(null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in [
      ('PlusJakartaSans', 'assets/fonts/PlusJakartaSans.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(entry.$1)..addFont(rootBundle.load(entry.$2))).load();
    }
  });
  testWidgets(
    'customer can sign up, edit profile, sign out, and sign back in through the actual app root',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = _CustomerSession();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authControllerProvider.overrideWith(() => session)],
          child: const D2FApp(),
        ),
      );
      await tester.pumpAndSettle();
      // Enter signup from login so the pushed signup route must be dismissed.
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Don’t have an account?'));
      await tester.pumpAndSettle();
      expect(find.byType(SignupScreen), findsOneWidget);
      for (final entry in [
        ('signup-name', 'Test Customer'),
        ('signup-email', 'customer@example.test'),
        ('signup-phone', '90000000'),
        ('signup-password', 'Customer-password-123'),
        ('signup-confirm-password', 'Customer-password-123'),
      ]) {
        await tester.enterText(find.byKey(ValueKey(entry.$1)), entry.$2);
      }
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Customer workspace transition',
      );
      expect(find.byType(RoleWorkspaceScreen), findsOneWidget);
      expect(find.byType(SignupScreen), findsNothing);
      expect(find.byType(StaffShell), findsNothing);
      expect(session.saved!.role, UserRole.CUSTOMER);
      expect(session.saved!.phone, '+22890000000');
      await tester.tap(find.byKey(const ValueKey('nav-profile')));
      await tester.pumpAndSettle();
      expect(find.text('CUSTOMER'), findsOneWidget);
      expect(find.text('Assigned location'), findsNothing);
      expect(find.text('Advanced connection'), findsNothing);
      await tester.tap(find.text('Edit profile'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your name.'), findsOneWidget);
      expect(session.updates, 0);
      await tester.enterText(fields.at(0), 'Updated Customer');
      await tester.enterText(fields.at(1), '+22890909090');
      session.failSave = true;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save your profile. Please try again.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(fields.first).controller!.text,
        'Updated Customer',
      );
      session.failSave = false;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Updated Customer'), findsOneWidget);
      expect(find.text('+22890909090'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Sign out'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out').last);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('staff-email')),
        'customer@example.test',
      );
      await tester.enterText(
        find.byKey(const ValueKey('staff-password')),
        'incorrect',
      );
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();
      expect(find.text('Invalid email or password.'), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('staff-password')),
        'Customer-password-123',
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();
      expect(session.remember, false);
      expect(
        tester.takeException(),
        isNull,
        reason: 'Customer workspace transition',
      );
      expect(find.byType(RoleWorkspaceScreen), findsOneWidget);
      expect(find.byType(StaffShell), findsNothing);
      await tester.tap(find.byKey(const ValueKey('nav-profile')));
      await tester.pumpAndSettle();
      expect(find.text('Updated Customer'), findsOneWidget);
      expect(find.text('CUSTOMER'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
