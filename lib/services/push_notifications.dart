import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/api.dart';

// Configure with FlutterFire's native files, or the FIREBASE_* dart defines.
// A missing project never prevents a user from opening their order history.
class PushNotifications {
  PushNotifications._();
  static final I = PushNotifications._();
  final status = ValueNotifier<String>('Notifications have not been enabled.');
  final messages = StreamController<RemoteMessage>.broadcast();
  final opened = StreamController<RemoteMessage>.broadcast();
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _foreground, _tap;
  String? _token, _owner;
  bool _ready = false;
  int _generation = 0;

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> connect(String owner) async {
    if (_owner == owner && _ready) return;
    final generation = ++_generation;
    _owner = owner;
    if (!supported) {
      status.value = 'Updates are available in your notification inbox.';
      return;
    }
    try {
      if (Firebase.apps.isEmpty) {
        const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
        await Firebase.initializeApp(
          options: apiKey.isEmpty
              ? null
              : const FirebaseOptions(
                  apiKey: apiKey,
                  appId: String.fromEnvironment('FIREBASE_APP_ID'),
                  messagingSenderId: String.fromEnvironment(
                    'FIREBASE_MESSAGING_SENDER_ID',
                  ),
                  projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
                  iosBundleId: String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
                ),
        );
      }
      if (generation != _generation) return;
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (generation != _generation) return;
      if (![
        AuthorizationStatus.authorized,
        AuthorizationStatus.provisional,
      ].contains(permission.authorizationStatus)) {
        status.value = 'Push is off. Enable notifications in your device settings. Your updates remain in the inbox.';
        return;
      }
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );
      Future<void> register(String token) async {
        if (generation != _generation || Api.I.sessionToken == null) return;
        await Api.I.registerPushDevice(
          token,
          defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        );
        if (generation == _generation) {
          _token = token;
          _ready = true;
          status.value =
              'Push notifications are enabled for all your D2F updates.';
        }
      }

      await _refresh?.cancel();
      // The Admin SDK sender needs an FCM registration token, not an installation ID.
      // ignore: deprecated_member_use
      _refresh = messaging.onTokenRefresh.listen((token) async {
        try {
          await register(token);
        } catch (_) {
          status.value =
              'Push registration needs a retry. Your inbox is available.';
        }
      });
      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      if (token != null) await register(token);
      if (generation != _generation) return;
      await _foreground?.cancel();
      await _tap?.cancel();
      _foreground = FirebaseMessaging.onMessage.listen(messages.add);
      _tap = FirebaseMessaging.onMessageOpenedApp.listen(opened.add);
      final initial = await messaging.getInitialMessage();
      if (initial != null && generation == _generation) opened.add(initial);
    } catch (_) {
      if (generation == _generation) status.value = 'Push setup is unavailable. All updates are saved in your notification inbox. Tap to retry.';
    }
  }

  Future<void> retry() async {
    final owner = _owner;
    _ready = false;
    if (owner != null) await connect(owner);
  }

  Future<void> disconnect() async {
    ++_generation;
    _owner = null;
    _ready = false;
    await _refresh?.cancel();
    await _foreground?.cancel();
    await _tap?.cancel();
    final token = _token;
    _token = null;
    if (token != null) {
      try {
        await Api.I
            .unregisterPushDevice(token)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        /* Token deletion below also revokes provider delivery. */
      }
    }
    if (Firebase.apps.isNotEmpty && supported) {
      try {
        // ignore: deprecated_member_use
        await FirebaseMessaging.instance.deleteToken().timeout(
          const Duration(seconds: 3),
        );
      } catch (_) {
        /* Offline devices re-register on next sign-in. */
      }
    }
    status.value = 'Notifications have not been enabled.';
  }
}
