import 'package:d2f_application/core/api.dart';
import 'package:d2f_application/core/theme.dart';
import 'package:d2f_application/models/marketplace.dart';
import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/providers/auth_provider.dart';
import 'package:d2f_application/screens/marketplace/buy_for_me_request_form.dart';
import 'package:d2f_application/screens/marketplace/buy_for_me_shop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Customer extends AuthController {
  @override
  Future<User?> build() async => const User(
    id: 'buyer',
    email: 'buyer@example.test',
    fullName: 'Buyer',
    role: UserRole.CUSTOMER,
  );
}

void main() {
  setUpAll(() async {
    for (final font in [
      ('PlusJakartaSans', 'assets/fonts/PlusJakartaSans.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  Widget app(Widget home, {double scale = 1.4}) => ProviderScope(
    overrides: [authControllerProvider.overrideWith(_Customer.new)],
    child: MaterialApp(
      theme: AppTheme.build(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    ),
  );
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 50,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets(
    'purchase form fits a small phone with large text and rejects non-finite budgets',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(app(const BuyForMeRequestFormScreen()));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('purchase-budget')));
      await tester.enterText(
        find.byKey(const ValueKey('purchase-budget')),
        'NaN',
      );
      await reveal(tester, find.text('Send request'));
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid amount.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'buyer reviews a long quote, recovers from a failed acceptance and reaches payment instructions',
    (tester) async {
      phone(tester);
      var state = 'QUOTED', fail = true;
      final decisions = <String>[];
      MarketplaceOrder order() => MarketplaceOrder.fromJson({
        'id': 'purchase',
        'kind': 'BUY_FOR_ME',
        'title': 'Laptop with accessories, extended warranty and protective carrying case',
        'status': state,
        'quantity': 1,
        'currency': 'USD',
        'amountMinor': 123456789,
        'productCostMinor': 123450000,
        'shippingCostMinor': 6789,
        'paymentInstructions': 'Contact D2F for verified payment instructions.',
        'paymentStatus': 'NOT_SUBMITTED',
        'deliveryAddress': '123 Example Street',
        'deliveryCity': 'Lomé',
        'deliveryCountry': 'Togo',
        'createdAt': '2026-11-12T10:00:00Z',
      });
      await tester.pumpWidget(
        app(
          Scaffold(
            body: BuyForMeShop(
              loadRequests: () async => [order()],
              decideRequest: (id, decision) async {
                decisions.add(decision);
                if (fail) {
                  throw ApiException(
                    'Connection interrupted. Please try again.',
                  );
                }
                state = 'ACCEPTED';
                return order();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = find.textContaining('Laptop with accessories');
      await reveal(tester, title);
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(find.text('What happens next'), findsOneWidget);
      await reveal(tester, find.textContaining('Accept quote ·'));
      await tester.tap(find.textContaining('Accept quote ·'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept quote'));
      await tester.pumpAndSettle();
      expect(
        find.text('Connection interrupted. Please try again.'),
        findsOneWidget,
      );
      fail = false;
      await tester.tap(find.textContaining('Accept quote ·'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept quote'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Payment instructions'));
      expect(
        find.text('Contact D2F for verified payment instructions.'),
        findsOneWidget,
      );
      expect(decisions, ['accept', 'accept']);
      expect(tester.takeException(), isNull);
    },
  );
}
