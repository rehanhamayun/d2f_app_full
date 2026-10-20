import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../models/models.dart';

/// Global session state. `null` = signed out, `User` = signed in.
class AuthController extends AsyncNotifier<User?> {
  @override
  Future<User?> build() => Api.I.restoreSession();

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

  Future<void> signOut() async {
    await Api.I.signOut();
    state = const AsyncData(null);
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, User?>(
  AuthController.new,
);
