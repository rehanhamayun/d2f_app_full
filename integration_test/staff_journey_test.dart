import 'package:d2f_application/core/api.dart';
import 'package:d2f_application/core/theme.dart';
import 'package:d2f_application/main.dart' as app;
import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/screens/parcel_success_screen.dart';
import 'package:d2f_application/screens/ship_screen.dart';
import 'package:d2f_application/screens/home_screen.dart';
import 'package:d2f_application/screens/label_preview_screen.dart';
import 'package:d2f_application/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'M1 staff journey preserves registration, lookup and event history',
    (tester) async {
      // Use the field's editing controller to avoid Android 16 IME resending stale
      // editing values while integration_test switches screenshot surfaces.
      Future<void> fill(Finder finder, String value) async {
        final editable = find.descendant(
          of: finder,
          matching: find.byType(EditableText),
        );
        tester.widget<EditableText>(editable).controller.text = value;
        await tester.pump();
      }

      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 600 && finder.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        if (finder.evaluate().isEmpty) {
          await binding.takeScreenshot('failure-state');
        }
        expect(finder, findsWidgets);
        await tester.pumpAndSettle();
      }

      Future<void> tapText(String text) async {
        if (find.text(text).evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            find.text(text),
            180,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.pumpAndSettle();
        }
        final finder = find.text(text).last;
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        debugPrint('UI CHECK: $name');
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

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.build(), home: const SplashScreen()),
      );
      await tester.runAsync(() async {
        final context = tester.element(find.byType(SplashScreen));
        await Future.wait([
          for (final asset in [
            'journey.jpg',
            'warehouse.jpg',
            'login.jpg',
            'parcel.jpg',
            'success.jpg',
            'd2f_2.png',
            'd2f_3.png',
          ])
            precacheImage(AssetImage('assets/images/$asset'), context),
        ]);
      });
      await tester.pump(const Duration(seconds: 2));
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('00a-splash-journey');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: const SplashScreen(stage: 1),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await binding.takeScreenshot('00b-splash-connected');
      await tester.pumpWidget(const SizedBox.shrink());
      await Api.I.init();
      await Api.I.signOut();
      app.main();
      // A fresh install always plays the brand ident, then the welcome intro
      // (three onboarding pages). Returning staff skip straight to the
      // workspace, so advance to sign-in the same way a new user would.
      for (
        var i = 0;
        i < 120 &&
            find.byKey(const ValueKey('splash-sign-in')).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      if (find.byKey(const ValueKey('splash-sign-in')).evaluate().isNotEmpty) {
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('splash-sign-in')));
        await tester.pumpAndSettle();
      }
      await waitFor(find.text('Welcome back.'));
      await fill(
        find.byKey(const ValueKey('staff-email')),
        'staff@d2fshipping.com',
      );
      await capture('01-login');
      await fill(
        find.byKey(const ValueKey('staff-password')),
        'incorrect-password',
      );
      await hideKeyboard();
      await tapText('Sign In');
      await waitFor(find.text('Invalid credentials'));
      await capture('01b-invalid-login');

      await fill(
        find.byKey(const ValueKey('staff-password')),
        const String.fromEnvironment(
          'TEST_STAFF_PASSWORD',
          defaultValue: 'Staff@2026',
        ),
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('staff-password')))
            .controller!
            .text,
        const String.fromEnvironment(
          'TEST_STAFF_PASSWORD',
          defaultValue: 'Staff@2026',
        ),
      );
      await hideKeyboard();
      await tapText('Sign In');
      await waitFor(find.text('STAFF WORKSPACE'));
      await capture('02-home');
      await tester.scrollUntilVisible(
        find.text('Marketplace'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await capture('02b-future-services');
      await tapText('Marketplace');
      await capture('02c-marketplace-coming-soon');
      await tapText('Got it');
      await tapText('Buy For Me');
      expect(find.textContaining('Buy For Me is coming'), findsOneWidget);
      await tapText('Got it');

      await tapText('Sea');
      await waitFor(find.text('Customer Information'));
      await capture('03-register-top');
      final customerName =
          'Emulator QA ${DateTime.now().millisecondsSinceEpoch}';
      await tapText('Add');
      await fill(field('Full name *'), customerName);
      await hideKeyboard();
      await tapText('Save');
      await waitFor(find.text(customerName));

      await reveal(field('Enter recipient name'));
      await fill(field('Enter recipient name'), 'UI verification recipient');
      await hideKeyboard();
      await reveal(field('Enter phone'));
      await fill(field('Enter phone'), '+22890000000');
      await hideKeyboard();
      await reveal(field('Enter full address'));
      await fill(
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
      await fill(field('Enter weight'), '2.5');
      await hideKeyboard();
      await reveal(field('E.g. contents, special instructions, etc.'));
      await fill(
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
      await tester.tap(find.byTooltip('Shipping label'));
      await waitFor(find.byType(LabelPreviewScreen));
      await tester.pump(const Duration(seconds: 3));
      await capture('06b-shipping-label');
      await tester.pageBack();
      await tester.pumpAndSettle();
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
      await fill(note, 'UI verification - prepared at Omaha warehouse.');
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
      await capture('10b-return-to-workspace');
      await tapText('Home');
      final lookupHomeScroll = find
          .descendant(
            of: find.byType(HomeScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(lookupHomeScroll).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tapText('Track parcel');
      await tester.pump(const Duration(seconds: 2));
      // The emulator uses a virtual camera; printed-code scanning requires physical hardware.
      await tester.pump();
      final manual = find.byType(TextField);
      await tester.ensureVisible(manual);
      await tester.pumpAndSettle();
      await fill(manual, parcel.trackingId);
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
      await tapText('Profile');
      await capture('13-profile');
      await tapText('Edit profile');
      await capture('13b-edit-profile');
      await tapText('Save');
      for (
        var i = 0;
        i < 200 && find.byType(AlertDialog).evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(AlertDialog), findsNothing);
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
      binding.reportData ??= {};
      binding.reportData!.addAll({
        'parcelId': parcel.id,
        'trackingId': parcel.trackingId,
        'customerId': parcel.customerId,
        'customerName': customerName,
      });
    },
  );
}
