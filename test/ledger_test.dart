import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/ledger.dart';

void main() {
  test(
    'filtered history excludes pending transfers and keeps cent precision',
    () {
      final rows = [
        {'kind': 'Debt', 'amount': 100.25, 'discount': 10.05, 'paidNow': 20.55},
        {'kind': 'Payment', 'amount': 90.20},
        {'kind': 'Payment', 'amount': 500, 'pendingConfirmation': true},
        {'kind': 'Return', 'amount': 12},
      ];
      expect(historyTotals(rows, supplier: false), {
        'invoices': 90.20,
        'received': 110.75,
        'paid': 0,
        'pendingCount': 1,
      });
      expect(historyTotals(rows, supplier: true)['paid'], 110.75);
    },
  );
  test('quantities support Arabic digits with three decimals', () {
    expect(quantityMillis('٢٫٥٢٥'), 2525);
    expect(quantityMillis('۰.۵'), 500);
    expect(quantityMillis('1.0001'), isNull);
    expect(quantityMillis('0'), isNull);
    expect(quantityText(1500), '1.5');
  });
  test('line totals round half up in integer cents', () {
    const p = InvoiceLine(
      id: 'p',
      name: 'أرز',
      unit: 'كغم',
      price: 1250,
      quantity: 2500,
    );
    expect(p.total, 3125);
    expect(p.withQuantity(1).total, 1);
    expect(
      const InvoiceLine(
        id: 'p',
        name: 'صنف',
        unit: 'كغم',
        price: 1000,
        quantity: 1005,
      ).total,
      1005,
    );
    expect(
      const InvoiceLine(
        id: 'p',
        name: 'صنف',
        unit: 'كغم',
        price: 500,
        quantity: 1,
      ).total,
      1,
    );
  });
  test('saved item snapshots do not follow product price changes', () {
    final product = <String, dynamic>{
      'id': 'p',
      'name': 'أرز',
      'unit': 'كغم',
      'salePrice': 12.5,
    };
    final p = InvoiceLine.product(product, false);
    product['salePrice'] = 20;
    expect(p.price, 1250);
    expect(InvoiceLine.fromJson(p.toJson()).price, 1250);
  });
  test('cash change requires explicit credit choice', () {
    expect(effectivePayment(7000, 10000, false), 7000);
    expect(effectivePayment(7000, 10000, true), 10000);
    expect(effectivePayment(7000, 2000, true), 7000);
  });
  test('running balance includes opening and zero pending delta', () {
    final entries = runningStatement({
      'openingBalance': 10,
      'entries': [
        {'delta': 25.5},
        {'delta': 0, 'pendingConfirmation': true},
        {'delta': -50},
      ],
    });
    expect(entries.map((e) => e['balanceAfter']), [35.5, 35.5, -14.5]);
  });
}
