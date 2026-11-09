import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deenbook/ui/party_lookup_field.dart';

void main() {
  testWidgets('customers are filtered and selected inside the same screen', (
    tester,
  ) async {
    final people = <Map<String, dynamic>>[
      {'id': '1', 'name': 'أحمد النجار', 'nickname': '', 'phone': '0591234567'},
      {'id': '2', 'name': 'ليان العصمي', 'nickname': 'ليان', 'phone': '0599999999'},
    ];
    Map<String, dynamic>? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, rebuild) => SingleChildScrollView(
              child: PartyLookupField(
                label: 'الزبون',
                selected: chosen,
                search: (query) async => people
                    .where((p) => '${p['name']}'.contains(query))
                    .toList(),
                onSelected: (next) => rebuild(() => chosen = next),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('transaction-party-search')));
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(find.text('أحمد النجار'), findsOneWidget);
    expect(find.text('ليان العصمي'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('transaction-party-search')),
      'ليان',
    );
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(find.text('أحمد النجار'), findsNothing);
    await tester.tap(find.text('ليان العصمي'));
    await tester.pumpAndSettle();

    expect(chosen?['id'], '2');
    expect(find.text('تم اختيار الزبون: ليان العصمي'), findsOneWidget);
    expect(find.byType(Navigator), findsOneWidget); // No new route opened.

    // Editing the name clears the selected party ID; a new suggestion must be
    // selected to avoid saving a transaction against the previous customer.
    await tester.enterText(
      find.byKey(const Key('transaction-party-search')),
      'زبون آخر',
    );
    await tester.pump();
    expect(chosen, isNull);
  });
}
