import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/report_kinds.dart';
import 'package:deenbook/core/ledger.dart';
import 'package:deenbook/core/offline_projection.dart';

void main() {
  test('TC-45: customer and supplier report filters use the correct kinds', () {
    expect(reportKindsFor('Customer'), {
      'all': 'كل الحركات', 'Debt': 'دين', 'Payment': 'دفعة', 'Return': 'مرتجع',
    });
    expect(reportKindsFor('Supplier'), {
      'all': 'كل الحركات', 'Purchase': 'مشتريات',
      'Payment': 'دفعة لمورد', 'Return': 'مرتجع',
    });
    expect(reportKindsFor('Customer').containsKey('Purchase'), isFalse);
    expect(reportKindsFor('Supplier').containsKey('Debt'), isFalse);
    expect(reportKindLabel('Supplier', 'Payment'), 'دفعة لمورد');
  });

  test('TC-45: supplier returns do not count as payments or new invoices', () {
    final totals = historyTotals([
      {'kind': 'Purchase', 'amount': 500, 'paidNow': 100},
      {'kind': 'Payment', 'amount': 50},
      {'kind': 'Return', 'amount': 75},
      {'kind': 'Return', 'amount': 25, 'voidedAt': '2026-11-20T00:00:00Z'},
    ], supplier: true);
    expect(totals['invoices'], 500);
    expect(totals['paid'], 150);
    expect(totals['returns'], 75);
    // A supplier return reduces the supplier payable balance like a credit.
    final entry = OfflineProjection.entry({
      'operationId': 'r1', 'partyId': 'supplier-1',
      'kind': 'Return', 'amount': 75,
    });
    expect(entry['delta'], -75);
  });

  test('TC-45: pending transfers are excluded from confirmed reports', () {
    final base = <String, dynamic>{'items': [], 'total': 0};
    final rows = [
      {'partyId': 'c', 'kind': 'Payment', 'amount': 10,
       'operationId': 'one', 'pendingConfirmation': false},
      {'partyId': 'c', 'kind': 'Payment', 'amount': 20,
       'operationId': 'two', 'pendingConfirmation': true},
    ];
    final result = OfflineProjection.transactionList(base, rows,
        {'pending': false, 'partyKind': 'Customer'}, {'c': 'Customer'});
    expect((result['items'] as List).length, 1);
    expect((result['items'] as List).first['amount'], 10);
  });
}
