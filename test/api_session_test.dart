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
  var role = 'CUSTOMER';

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
    role = 'CUSTOMER';
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
              'role': role,
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

  test('offline staff identity unlocks cached printing only and sign-out purges cached labels', () async {
    role = 'STAFF';
    await Api.I.signIn('staff@example.test', 'test-password');
    sessionStatus = HttpStatus.serviceUnavailable;
    final user = await Api.I.restoreSession();
    expect(user?.isStaff, true);
    expect(Api.I.offlinePrintingOnly, true);
    expect(Api.I.offlinePrintingUser?.id, 'session-test');
    await expectLater(
      Api.I.shipmentOperation('/parcels'),
      throwsA(isA<ApiException>()),
    );
    await Api.I.signOut();
    expect(Api.I.offlinePrintingUser, isNull);
    expect(Api.I.offlinePrintingOnly, false);
    expect(
      await const FlutterSecureStorage().read(key: 'd2f_print_identity_v1'),
      isNull,
    );
  });
  test('server rejection and changing API origin invalidate offline operational identity', () async {
    role = 'STAFF';
    await Api.I.signIn('staff@example.test', 'test-password');
    expect(Api.I.offlinePrintingUser, isNotNull);
    sessionStatus = HttpStatus.unauthorized;
    expect(await Api.I.restoreSession(), isNull);
    expect(Api.I.offlinePrintingUser, isNull);
    await Api.I.signIn('staff@example.test', 'test-password');
    await Api.I.setBaseUrl('http://localhost:${server.port}');
    expect(Api.I.offlinePrintingUser, isNull);
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
