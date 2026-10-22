import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:d2f_application/core/api.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  HttpOverrides? previousHttpOverrides;
  var sessionStatus = HttpStatus.ok;
  Completer<void>? sessionGate;
  Completer<void>? sessionStarted;
  var loginCount = 0;

  setUpAll(() async {
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    FlutterSecureStorage.setMockInitialValues({});
    await Api.I.init();
  });

  tearDownAll(() {
    HttpOverrides.global = previousHttpOverrides;
  });

  setUp(() async {
    sessionStatus = HttpStatus.ok;
    sessionGate = null;
    sessionStarted = null;
    loginCount = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/auth/login') {
        request.response.write(
          jsonEncode({
            'token': 'session-${++loginCount}',
            'user': {
              'id': 'session-test',
              'fullName': 'Session Test',
              'email': 'session@example.test',
              'role': 'CUSTOMER',
            },
          }),
        );
      } else {
        sessionStarted?.complete();
        await sessionGate?.future;
        request.response.statusCode = sessionStatus;
        request.response.write(jsonEncode({'error': 'Session unavailable'}));
      }
      await request.response.close();
    });
    await Api.I.setBaseUrl('http://127.0.0.1:${server.port}');
    await Api.I.signIn('session@example.test', 'test-password');
  });

  tearDown(() async {
    await server.close(force: true);
    await Api.I.signOut();
    await Api.I.setBaseUrl('');
  });

  test('a server outage preserves the remembered session', () async {
    sessionStatus = HttpStatus.serviceUnavailable;
    expect(await Api.I.restoreSession(), isNull);
    expect(Api.I.sessionToken, 'session-1');
    expect(
      await const FlutterSecureStorage().read(key: 'd2f_jwt'),
      'session-1',
    );
  });

  test('a network failure preserves the remembered session', () async {
    await server.close(force: true);
    expect(await Api.I.restoreSession(), isNull);
    expect(Api.I.sessionToken, 'session-1');
  });

  test('a rejected session clears the remembered login', () async {
    sessionStatus = HttpStatus.unauthorized;
    expect(await Api.I.restoreSession(), isNull);
    expect(Api.I.sessionToken, isNull);
    expect(await const FlutterSecureStorage().read(key: 'd2f_jwt'), isNull);
  });

  test('a late rejected restore cannot clear a newer sign-in', () async {
    sessionStatus = HttpStatus.unauthorized;
    sessionGate = Completer<void>();
    sessionStarted = Completer<void>();
    final restoring = Api.I.restoreSession();
    await sessionStarted!.future;
    await Api.I.signIn('session@example.test', 'test-password');
    sessionGate!.complete();
    expect(await restoring, isNull);
    expect(Api.I.sessionToken, 'session-2');
  });
}
