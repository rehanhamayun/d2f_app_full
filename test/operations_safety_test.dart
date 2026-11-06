import 'package:d2f_application/core/theme.dart';
import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/screens/parcel_detail_screen.dart';
import 'package:d2f_application/widgets/connect_declaration_form.dart';
import 'package:d2f_application/widgets/operational_note_field.dart';
import 'package:d2f_application/widgets/structured_address_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/us_address.dart';

void main() {
  testWidgets(
    'pending parcel details never claim delivered and sea routes show a ship',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final status in [
        'REQUESTED',
        'PROCESSING',
        'READY_FOR_LOADING',
        'IN_TRANSIT',
        'DELIVERED',
      ]) {
        final p = Parcel.fromJson({
          'id': 'safety',
          'trackingId': 'D2F000000000027',
          'customerId': 'c',
          'recipientName': 'Recipient',
          'packageType': 'BOX',
          'weightKg': 3,
          'origin': 'Lomé, Togo',
          'destination': 'Omaha, USA',
          'method': 'SEA',
          'status': status,
          'createdAt': '2026-11-02T00:00:00Z',
          'updatedAt': '2026-11-02T00:00:00Z',
        });
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.build(),
              home: ParcelDetailScreen(
                key: ValueKey(status),
                parcelId: p.id,
                loadParcel: (_) async => p,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.flight_takeoff_rounded), findsNothing);
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -1800),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('This parcel is delivered — lifecycle complete.'),
          status == 'DELIVERED' ? findsOneWidget : findsNothing,
        );
        if (status == 'READY_FOR_LOADING') {
          expect(
            find.textContaining('Awaiting physical loading'),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'standard operational message and extra details are distinct; Other reveals a required custom entry',
    (tester) async {
      Map<String, dynamic> selected = {};
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: OperationalNoteField(
                status: 'PROCESSING',
                serviceType: 'SEA',
                onChanged: (v) => selected = v,
                request: (p, {method = 'GET', data}) async => [
                  {
                    'id': 'n1',
                    'message': 'Parcel stored securely awaiting shipment.',
                  },
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('operational-note-PROCESSING')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Parcel stored securely awaiting shipment.').last,
      );
      await tester.pumpAndSettle();
      expect(selected['noteTemplateId'], 'n1');
      await tester.enterText(find.byType(TextField), 'Shelf B-4');
      expect(selected['additionalDetails'], 'Shelf B-4');
      expect(selected.containsKey('customMessage'), false);
      await tester.tap(
        find.byKey(const ValueKey('operational-note-PROCESSING')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other - Custom Message').last);
      await tester.pumpAndSettle();
      expect(selected['customMessage'], '');
      expect(selected.containsKey('noteTemplateId'), false);
      await tester.enterText(
        find.byType(TextField),
        'Repacking required before staging.',
      );
      expect(selected['customMessage'], 'Repacking required before staging.');
    },
  );
  testWidgets(
    'declaration begins unchecked, blocks incomplete acknowledgment and resets when contents change',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, dynamic>? sent;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: ConnectDeclarationForm(
            bookingId: 'b',
            contents: '3 shirts; 2 pairs of shoes.',
            request: (path, {method = 'GET', data}) async {
              if (method == 'POST') {
                sent = data;
                return {};
              }
              return {
                'termsVersion': 'test-v1',
                'warning': 'Prohibited or falsely declared items may result in confiscation, fines or criminal prosecution.',
                'terms': 'D2F may inspect and refuse undeclared goods.',
                'checks': List.generate(
                  5,
                  (i) => 'Mandatory declaration ${i + 1}',
                ),
                'guidance': [
                  {
                    'title': 'Entering destination',
                    'message': 'Verify route restrictions before acceptance.',
                  },
                ],
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('declaration-confirm')),
            )
            .onPressed,
        isNull,
      );
      Future<void> show(Finder f, {double delta = 180}) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          f,
          delta,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
      }

      for (var i = 0; i < 5; i++) {
        final f = find.byKey(ValueKey('declaration-check-$i'));
        await show(f);
        expect(tester.widget<CheckboxListTile>(f).value, false);
        await tester.tap(f);
        await tester.pumpAndSettle();
      }
      final name = find.byKey(const ValueKey('declaration-legal-name'));
      await show(name);
      await tester.enterText(name, 'Alex Morgan');
      await tester.pumpAndSettle();
      final electronic = find.byKey(const ValueKey('declaration-electronic'));
      await show(electronic);
      await tester.tap(electronic);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('declaration-confirm')),
            )
            .onPressed,
        isNotNull,
      );
      final contents = find.byKey(const ValueKey('declaration-contents'));
      await show(contents, delta: -180);
      await tester.enterText(contents, '4 shirts; 2 pairs of shoes.');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('declaration-check-0')),
            )
            .value,
        false,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('declaration-confirm')),
            )
            .onPressed,
        isNull,
      );
      expect(sent, isNull);
    },
  );
  testWidgets(
    'US address validates individual fields and saves the complete formatted address',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final address = TextEditingController();
      addTearDown(address.dispose);
      final form = GlobalKey<FormState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: Scaffold(
            body: Form(
              key: form,
              child: SingleChildScrollView(
                child: StructuredAddressField(
                  controller: address,
                  label: 'US address',
                  isUs: true,
                  includeContact: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(form.currentState!.validate(), false);
      await fillUsAddress(tester, 'US address');
      expect(form.currentState!.validate(), true);
      expect(
        address.text,
        'Alex Morgan\n108 Dodge Street\nOmaha, NE 68104\nUnited States\nPhone: (402) 555-0123',
      );
      expect(tester.takeException(), isNull);
    },
  );
  test('sea generic status options never offer departure; air and road retain their separate workflows', () {
    Parcel p(String status, ShippingMethod method) => Parcel(
      id: 'p',
      trackingId: 'D2F000000000024',
      customerId: 'c',
      recipientName: 'Recipient',
      packageType: 'BOX',
      weightKg: 3,
      origin: 'Omaha, USA',
      destination: 'Lomé, Togo',
      method: method,
      status: status,
      warehouseReceivedAt: DateTime(2026),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    expect(staffStatusOptionsFor(p('PROCESSING', ShippingMethod.SEA)), [
      'READY_FOR_LOADING',
    ]);
    for (final s in [
      'READY_FOR_LOADING',
      'LOADED_IN_CONTAINER',
      'IN_TRANSIT',
      'ARRIVED_PORT',
      'CUSTOMS_CLEARANCE',
      'CUSTOMS_CLEARED',
    ]) {
      expect(staffStatusOptionsFor(p(s, ShippingMethod.SEA)), isEmpty);
    }
    expect(staffStatusOptionsFor(p('PROCESSING', ShippingMethod.AIR)), [
      'IN_TRANSIT',
    ]);
    expect(staffStatusOptionsFor(p('PROCESSING', ShippingMethod.ROAD)), [
      'IN_TRANSIT',
    ]);
  });
}
