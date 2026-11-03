import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> fillUsAddress(
  WidgetTester tester,
  String label, {
  String street = '108 Dodge Street',
  String city = 'Omaha',
  bool contact = true,
}) async {
  Future<void> reveal(Finder f) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      f,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  for (final entry in <String, String>{
    if (contact) 'first': 'Alex',
    if (contact) 'last': 'Morgan',
    'street': street,
    'city': city,
    'zip': '68104',
    if (contact) 'phone': '4025550123',
  }.entries) {
    final f = find.byKey(ValueKey('$label-${entry.key}'));
    await reveal(f);
    await tester.enterText(f, entry.value);
    await tester.pumpAndSettle();
  }
  final state = find.byKey(ValueKey('$label-state'));
  await reveal(state);
  await tester.tap(state);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Nebraska (NE)'),
    150,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(find.text('Nebraska (NE)'));
  await tester.pumpAndSettle();
}
