import 'package:deenbook/core/ledger.dart';
import 'package:deenbook/services/export.dart';
import 'package:deenbook/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> movement({bool voided = false}) => {
  'id': 'entry-1',
  'kind': 'Debt',
  'amount': 50.0,
  'discount': 0.0,
  'delta': 50.0,
  'paidNow': 0.0,
  'method': 'Cash',
  'occurredAt': '2026-11-21T10:00:00Z',
  'items': <dynamic>[],
  'partyId': 'customer-1',
  if (voided) ...{
    'voidedAt': '2026-11-21T12:00:00Z',
    'voidReason': 'تم تسجيل المشتريات بالخطأ',
  },
};

void main() {
  test('TC-40: a voided entry stays in the statement but does not change balance', () {
    final statement = <String, dynamic>{
      'openingBalance': 100.0,
      'entries': <Map<String, dynamic>>[
        {'id': 'a', 'kind': 'Debt', 'amount': 50.0, 'delta': 50.0},
        {'id': 'b', 'kind': 'Payment', 'amount': 30.0, 'delta': -30.0,
          'voidedAt': '2026-11-21T10:00:00Z', 'voidReason': 'بالخطأ'},
        {'id': 'c', 'kind': 'Payment', 'amount': 20.0, 'delta': -20.0},
      ],
    };
    final rows = runningStatement(statement);
    expect(rows.length, 3);
    expect(rows[0]['balanceAfter'], 150.0);
    expect(rows[1]['balanceAfter'], 150.0);
    expect(rows[2]['balanceAfter'], 130.0);
    final totals = historyTotals(rows, supplier: false);
    expect(totals['invoices'], 50.0);
    expect(totals['received'], 20.0);
  });

  testWidgets('TC-40: crossed-out movement still appears with reason', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: entryTile(movement(voided: true), name: 'حركة مسجلة بالخطأ', onVoid: () {}),
    )));
    expect(find.text('حركة مسجلة بالخطأ'), findsOneWidget);
    expect(find.byKey(const Key('tc40-voided-label')), findsOneWidget);
    expect(find.textContaining('سبب الشطب:'), findsOneWidget);
    final name = tester.widget<Text>(find.text('حركة مسجلة بالخطأ'));
    expect(name.style?.decoration, TextDecoration.lineThrough);
    expect(find.text('شطب الحركة'), findsNothing);
  });

  testWidgets('TC-40: void reason is mandatory before confirmation', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => TextButton(
        onPressed: () => askVoidReason(context),
        child: const Text('ابدأ الشطب'),
      )),
    )));
    await tester.tap(find.text('ابدأ الشطب'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tc40-void-only')));
    await tester.pumpAndSettle();
    expect(find.text('اكتب سبب الشطب أولًا'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('tc40-void-reason')), 'أضيفت الحركة بالخطأ');
    await tester.tap(find.byKey(const Key('tc40-void-only')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tc40-void-only')), findsNothing);
  });

  test('TC-40: voided movements are not present in CSV exports', () {
    final active = movement();
    final voided = movement(voided: true);
    final csv = Exports.historyCsvText([active, voided], {'customer-1': 'أحمد'});
    expect(csv.contains('سُجّلت الحركة بالخطأ'), isFalse);
    expect(csv.contains('تم تسجيل المشتريات بالخطأ'), isFalse);
    expect(csv.split('\r\n').length, 2); // Header + one active row.
  });
}
