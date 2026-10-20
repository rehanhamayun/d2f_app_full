import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../models/models.dart';

/// Global session state. `null` = signed out, `User` = signed in.
class AuthController extends AsyncNotifier<User?> {
  /// Bounded startup: a remembered session restores within this window or the
  /// sign-in screen appears quickly. A slow network can then never hold the
  /// splash screen for up to Dio's 30s connect timeout.
  static const Duration _restoreWindow = Duration(seconds: 5);

  @override
  Future<User?> build() async {
    if (Api.I.sessionToken == null) return null; // instant sign-in screen
    return Api.I.restoreSession().timeout(
      _restoreWindow,
      onTimeout: () => null, // fall through to the sign-in screen
    );
  }

  /// Signs in; on failure resets to signed-out and rethrows so the
  /// login screen can display the server's message.
  Future<User> signIn(
    String email,
    String password, {
    bool remember = true,
  }) async {
    // The login screen owns its loading state so failed attempts keep its form and error visible.
    final user = await Api.I.signIn(email, password, remember: remember);
    state = AsyncData(user);
    return user;
  }

  /// Creates a new account and immediately establishes the session.
  Future<User> signUp(
    String fullName,
    String email,
    String password, {
    String? phone,
  }) async {
    final user = await Api.I.signUp(fullName, email, password, phone: phone);
    state = AsyncData(user);
    return user;
  }

  Future<void> updateProfile(String name, String? phone) async {
    state = AsyncData(await Api.I.updateProfile(fullName: name, phone: phone));
  }

  Future<void> signOut() async {
    await Api.I.signOut();
    state = const AsyncData(null);
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, User?>(
  AuthController.new,
);
