import 'dart:convert';

import 'package:d2f_application/core/theme.dart';
import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/providers/auth_provider.dart';
import 'package:d2f_application/screens/direct_label_print_screen.dart';
import 'package:d2f_application/services/direct_label_print.dart';
import 'package:d2f_application/widgets/connect_payment_evidence.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

const staff = User(
  id: 'print-staff',
  email: 'staff@example.test',
  fullName: 'Staff',
  role: UserRole.STAFF,
);

class PrintAuth extends AuthController {
  final User user;
  PrintAuth(this.user);
  @override
  Future<User?> build() async => user;
}

void main() {
  testWidgets(
    'screenshot evidence activates a safe submit button and preserves transaction ID',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 32);
      addTearDown(tester.view.reset);
      ImageSource? picked;
      Map<String, dynamic>? sent;
      final image = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jWZkAAAAASUVORK5CYII=',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ConnectPaymentEvidenceForm(
                      bookingId: 'b',
                      instructions: 'Pay the verified D2F account.',
                      version: 1,
                      pickImage: (source) async {
                        picked = source;
                        return image;
                      },
                      submit:
                          ({
                            required method,
                            required transactionId,
                            required bytes,
                          }) async {
                            sent = {
                              'method': method,
                              'transactionId': transactionId,
                              'bytes': bytes,
                            };
                          },
                    ),
                  ),
                ),
                child: const Text('Open payment'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open payment'));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('payment-evidence-submit'));
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zelle').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'TX-123');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('payment-camera')));
      await tester.tap(find.byKey(const ValueKey('payment-camera')));
      await tester.pumpAndSettle();
      expect(picked, ImageSource.gallery);
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      expect(tester.getBottomLeft(button).dy, lessThanOrEqualTo(844 - 32));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(sent?['method'], 'ZELLE');
      expect(sent?['transactionId'], 'TX-123');
      expect(sent?['bytes'], image);
      expect(find.text('Open payment'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'denied photo access shows permission instructions and keeps submit disabled',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ConnectPaymentEvidenceForm(
            bookingId: 'b',
            instructions: 'Instructions',
            version: 1,
            pickImage: (_) async =>
                throw PlatformException(code: 'photo_access_denied'),
          ),
        ),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('payment-camera')));
      await tester.tap(find.byKey(const ValueKey('payment-camera')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Android Settings'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('payment-evidence-submit')),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'printer settings load for staff and customers cannot use operational printing',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DirectLabelPrint.channel, (call) async {
            calls.add(call.method);
            if (call.method == 'settings')
              return {'sdkVersion': '4.13.2', 'defaultPrinter': null};
            if (call.method == 'paired')
              return [
                {
                  'address': 'AA:BB:CC:DD:EE:FF',
                  'name': 'Brother QL-1110NWB',
                  'paired': true,
                },
              ];
            return call.method == 'permissions' ? true : [];
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(DirectLabelPrint.channel, null),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(() => PrintAuth(staff)),
          ],
          child: MaterialApp(
            theme: AppTheme.build(),
            home: const DirectLabelPrintScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Choose your Brother printer'), findsOneWidget);
      await tester.tap(find.text('Refresh paired printers'));
      await tester.pumpAndSettle();
      expect(
        calls,
        containsAllInOrder([
          'settings',
          'cachedLabels',
          'history',
          'permissions',
          'paired',
        ]),
      );
      expect(find.text('Save default'), findsOneWidget);
      expect(calls, isNot(contains('print')));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      calls.clear();
      const customer = User(
        id: 'customer',
        email: 'customer@example.test',
        fullName: 'Customer',
        role: UserRole.CUSTOMER,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(() => PrintAuth(customer)),
          ],
          child: const MaterialApp(home: DirectLabelPrintScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Sign in as staff'), findsOneWidget);
      expect(calls, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    },
  );
  test('explicit reprint carries reason and unique client job ID to the native ledger', () async {
    final calls = <Map<String, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DirectLabelPrint.channel, (call) async {
          calls.add(Map<String, dynamic>.from(call.arguments));
          return {'status': 'FAILED', 'message': 'Synthetic test; no hardware'};
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DirectLabelPrint.channel, null),
    );
    await DirectLabelPrint.print(staff, 'p1', 'D2F1');
    await DirectLabelPrint.print(
      staff,
      'p1',
      'D2F1',
      reprint: true,
      reason: 'Damaged label',
    );
    expect(calls.first['reprint'], false);
    expect(calls.last['reason'], 'Damaged label');
    expect(calls.last['reprint'], true);
    expect(calls.first['clientJobId'], isNot(calls.last['clientJobId']));
    expect(calls.first['ownerId'], endsWith(':print-staff'));
  });
}
