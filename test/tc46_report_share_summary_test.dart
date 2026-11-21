import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/report_share_summary.dart';

void main() {
  String summary({
    String partyKind = 'Customer',
    String? partyName = 'أحمد',
    String? kind,
    num? balance = 250,
    num? outstanding,
    Map<String, dynamic>? totals,
    bool pendingOnly = false,
    int pendingLocal = 0,
  }) => buildReportShareSummary(
    shopName: 'محل السعادة',
    partyKind: partyKind,
    periodLabel: 'الفترة: هذا الشهر',
    overview: totals ?? {
      'invoices': 500, 'received': 200, 'paid': 0,
      'returns': 50, 'pendingCount': 0,
    },
    partyName: partyName,
    kind: kind,
    currentBalance: balance,
    groupOutstanding: outstanding,
    pendingOnly: pendingOnly,
    pendingLocal: pendingLocal,
  );

  test('TC-46: selected customer with debt - no supplier labels or zero rows', () {
    final text = summary();
    expect(text, contains('المشتريات: 500.00 ₪'));
    expect(text, contains('الدفعات المؤكدة من الزبائن: 200.00 ₪'));
    expect(text, contains('المرتجعات: 50.00 ₪'));
    expect(text, contains('المبلغ المستحق على الزبون: 250.00 ₪'));
    expect(text, isNot(contains('مدفوع للموردين')));
    expect(text, isNot(contains('الفواتير')));
    expect(text, isNot(contains(': 0.00 ₪'))); // no irrelevant zero rows
  });

  test('TC-46: a customer in credit has no outstanding debt', () {
    final text = summary(balance: -125.5);
    expect(text, contains('رصيد للزبون لدينا: 125.50 ₪'));
    expect(text, isNot(contains('المبلغ المستحق على الزبون:')));
  });

  test('TC-46: settled customer is stated clearly', () {
    final text = summary(balance: 0, totals: {
      'invoices': 0, 'received': 0, 'returns': 0,
    });
    expect(text, contains('حساب الزبون مسدّد بالكامل.'));
    expect(text, contains('لا توجد حركات مالية مؤكدة'));
    expect(text, isNot(contains(': 0.00 ₪')));
  });

  test('TC-46: supplier summary has its own terminology and balance signs', () {
    final text = summary(
      partyKind: 'Supplier', partyName: 'شركة النور', balance: 325,
      totals: {'invoices': 500, 'paid': 100, 'received': 0, 'returns': 75},
    );
    expect(text, contains('الفواتير: 500.00 ₪'));
    expect(text, contains('المدفوع للموردين: 100.00 ₪'));
    expect(text, contains('المرتجعات: 75.00 ₪'));
    expect(text, contains('المستحق للمورد: 325.00 ₪'));
    expect(text, isNot(contains('المبلغ المستحق على الزبون')));
    expect(text, isNot(contains('الدفعات المؤكدة من الزبائن')));
    final credit = summary(partyKind: 'Supplier', balance: -40);
    expect(credit, contains('رصيد لنا لدى المورد: 40.00 ₪'));
  });

  test('TC-46: all customers show only current aggregate outstanding', () {
    final text = summary(partyName: null, balance: null, outstanding: 800);
    expect(text, contains('إجمالي المبالغ المستحقة على الزبائن: 800.00 ₪'));
    expect(text, isNot(contains('المبلغ المستحق على الزبون:')));
    expect(text, contains('الأرصدة الحالية'));
  });

  test('TC-46: filters and pending items do not contaminate confirmed totals', () {
    final text = summary(
      kind: 'Payment', pendingOnly: true, pendingLocal: 2,
      totals: {'invoices': 0, 'received': 0, 'paid': 0, 'returns': 0, 'pendingCount': 3},
    );
    expect(text, contains('نوع الحركة: دفعة'));
    expect(text, contains('الحوالات بانتظار التأكيد: 3'));
    expect(text, contains('2 حركة محلية بانتظار المزامنة'));
    expect(text, isNot(contains('الفواتير')));
  });
}
