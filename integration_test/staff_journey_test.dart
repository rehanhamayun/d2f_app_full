import 'package:d2f_application/core/api.dart';
import 'package:d2f_application/main.dart' as app;
import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/screens/parcel_success_screen.dart';
import 'package:d2f_application/screens/ship_screen.dart';
import 'package:d2f_application/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'M1 staff journey preserves registration, lookup and event history',
    (tester) async {
      await Api.I.init();
      await Api.I.signOut();
      final preflight = await Api.I.signIn(
        'staff@d2fshipping.com',
        const String.fromEnvironment(
          'TEST_STAFF_PASSWORD',
          defaultValue: 'Staff@2026',
        ),
      );
      expect(preflight.isStaff, isTrue);
      await Api.I.signOut();
      app.main();

      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 600 && finder.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(finder, findsWidgets);
        await tester.pumpAndSettle();
      }

      Future<void> tapText(String text) async {
        final finder = find.text(text).last;
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        await binding.takeScreenshot(name);
        expect(tester.takeException(), isNull);
      }

      Future<void> hideKeyboard() async {
        FocusManager.instance.primaryFocus?.unfocus();
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await tester.pumpAndSettle();
      }

      Future<void> reveal(Finder finder) async {
        final scrollable = find
            .descendant(
              of: find.byType(ShipScreen),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(finder, 180, scrollable: scrollable);
        await tester.pumpAndSettle();
      }

      Finder field(String hint) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == hint,
      );

      await waitFor(find.text('Welcome back.'));
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await capture('01-login');
      await tester.enterText(
        find.byType(TextField).at(1),
        'incorrect-password',
      );
      await hideKeyboard();
      await tapText('Sign In');
      await waitFor(find.text('Invalid credentials'));
      await capture('01b-invalid-login');

      await tester.enterText(
        find.byType(TextField).at(1),
        const String.fromEnvironment(
          'TEST_STAFF_PASSWORD',
          defaultValue: 'Staff@2026',
        ),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        const String.fromEnvironment(
          'TEST_STAFF_PASSWORD',
          defaultValue: 'Staff@2026',
        ),
      );
      await hideKeyboard();
      await tapText('Sign In');
      await waitFor(find.text('STAFF WORKSPACE'));
      await capture('02-home');

      await tapText('Sea');
      await waitFor(find.text('Customer Information'));
      await capture('03-register-top');
      await tester.tap(find.byType(DropdownButtonFormField<Customer>));
      await tester.pumpAndSettle();
      await tapText('Koffi Mensah');

      await reveal(field('Enter recipient name'));
      await tester.enterText(
        field('Enter recipient name'),
        'UI verification recipient',
      );
      await hideKeyboard();
      await reveal(field('Enter phone'));
      await tester.enterText(field('Enter phone'), '+22890000000');
      await hideKeyboard();
      await reveal(field('Enter full address'));
      await tester.enterText(
        field('Enter full address'),
        'Lomé, Togo - local demo verification',
      );
      await hideKeyboard();

      final destination = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.hintText == 'Select destination',
      );
      await reveal(destination);
      await tester.tap(destination);
      await tester.pumpAndSettle();
      await tapText(kDestinationOptions.first);

      final package = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.hintText == 'Select package type',
      );
      await reveal(package);
      await tester.tap(package);
      await tester.pumpAndSettle();
      await tapText('Box');
      await reveal(field('Enter weight'));
      await tester.enterText(field('Enter weight'), '2.5');
      await hideKeyboard();
      await reveal(field('E.g. contents, special instructions, etc.'));
      await tester.enterText(
        field('E.g. contents, special instructions, etc.'),
        'Local emulator UI verification.',
      );
      await hideKeyboard();
      await reveal(find.text('Save Parcel'));
      await capture('04-register-shipment');
      await tapText('Save Parcel');
      await waitFor(find.byType(ParcelSuccessScreen));
      final parcel = tester
          .widget<ParcelSuccessScreen>(find.byType(ParcelSuccessScreen))
          .parcel;
      expect(parcel.trackingId, startsWith('D2F-'));
      expect(parcel.weightKg, 2.5);
      expect(parcel.method, ShippingMethod.SEA);
      expect(parcel.recipientName, 'UI verification recipient');
      await capture('05-registered-qr-barcode');
      await tapText('View Parcel');
      await waitFor(find.text('Shipment Information'));
      await capture('06-parcel-overview');
      await tapText('Tracking');
      expect(find.text('Tracking Timeline'), findsOneWidget);
      expect(find.text('Shipment Information'), findsNothing);
      await capture('07-tracking-timeline');
      await tapText('Details');
      expect(find.text('Full Details'), findsOneWidget);
      expect(find.text('Tracking Timeline'), findsNothing);
      await capture('08-parcel-details');
      await tapText('Overview');
      await tapText('Update Status');
      await waitFor(find.text('Select new status'));
      await capture('09-status-options');
      await tapText('Processing');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tapText(kEventLocations.first);
      final note = find.byType(TextField);
      await tester.ensureVisible(note);
      await tester.pumpAndSettle();
      await tester.enterText(
        note,
        'UI verification - prepared at Omaha warehouse.',
      );
      await hideKeyboard();
      await tapText('Update Status');
      await waitFor(find.text('Shipment Information'));
      final saved = await Api.I.parcelDetail(parcel.trackingId);
      expect(saved.id, parcel.id);
      expect(saved.status, 'PROCESSING');
      expect(
        saved.events.any(
          (e) => e.note == 'UI verification - prepared at Omaha warehouse.',
        ),
        isTrue,
      );
      await tapText('Tracking');
      await capture('10-persisted-event');

      // Return to the shell and find the same parcel through the actual manual lookup.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapText('Home');
      await tapText('Track parcel');
      await tester.pump(const Duration(seconds: 2));
      // Platform camera permission is intentionally not accepted by this test.
      await tester.pump();
      final manual = find.byType(TextField);
      await tester.ensureVisible(manual);
      await tester.pumpAndSettle();
      await tester.enterText(manual, parcel.trackingId);
      await hideKeyboard();
      await capture('11-scan-manual-lookup');
      await tapText('Find Parcel');
      await waitFor(find.text('Shipment Information'));
      expect(find.text(parcel.trackingId), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapText('Activity');
      await waitFor(find.text('Parcels'));
      await waitFor(find.text(parcel.trackingId));
      await capture('12-activity');
      await tapText('Account');
      await capture('13-account');
      await tapText('Home');
      final homeScroll = find
          .descendant(
            of: find.byType(HomeScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(homeScroll).position.jumpTo(0);
      await tester.pumpAndSettle();
      await capture('14-home-final');
      // Recreate the application and its ProviderScope; restore the stored session
      // and retrieve the same record from the backend.
      await tester.pumpWidget(const SizedBox.shrink());
      app.main();
      await waitFor(find.text('STAFF WORKSPACE'));
      final restored = await Api.I.parcelDetail(parcel.trackingId);
      expect(restored.id, parcel.id);
      expect(restored.status, 'PROCESSING');
      expect(restored.events.length, greaterThanOrEqualTo(2));
      await capture('15-restored-session');
    },
  );
}
