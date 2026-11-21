import 'format.dart';
import 'report_kinds.dart';
import 'collection_accounts.dart';

/// Format a report share draft from the same filtered totals as the visible
/// transaction report. Balances are current balances, not period totals.
/// Keep customer and supplier terminology completely separate.
String buildReportShareSummary({
  required String shopName,
  required String partyKind,
  required String periodLabel,
  required Map<String, dynamic> overview,
  String? partyName,
  String? kind,
  num? currentBalance,
  num? groupOutstanding,
  bool pendingOnly = false,
  int pendingLocal = 0,
  List<ShopCollectionAccount> collectionAccounts = const [],
}) {
  final supplier = partyKind == 'Supplier';
  final individual = partyName != null && partyName.trim().isNotEmpty;
  final lines = <String>[
    shopName,
    supplier ? 'ملخص حركات الموردين' : 'ملخص حركات الزبائن',
    periodLabel,
    individual
        ? '${supplier ? 'المورد' : 'الزبون'}: ${partyName!.trim()}'
        : supplier ? 'النطاق: جميع الموردين' : 'النطاق: جميع الزبائن',
    'نوع الحركة: ${reportKindLabel(partyKind, kind)}',
  ];
  final invoice = (overview['invoices'] as num?) ?? 0;
  final payment = (overview[supplier ? 'paid' : 'received'] as num?) ?? 0;
  final returned = (overview['returns'] as num?) ?? 0;
  final pending = (overview['pendingCount'] as num?) ?? 0;

  // Do not include irrelevant categories or zero-valued financial rows.
  final movements = <String>[
    if (invoice != 0) '${supplier ? 'الفواتير' : 'المشتريات'}: ${money(invoice)}',
    if (payment != 0)
      '${supplier ? 'المدفوع للموردين' : 'الدفعات المؤكدة من الزبائن'}: ${money(payment)}',
    if (returned != 0) 'المرتجعات: ${money(returned)}',
  ];
  if (movements.isEmpty) {
    lines.add('لا توجد حركات مالية مؤكدة ضمن الفلاتر المختارة.');
  } else {
    lines.addAll(movements);
  }
  if (pendingOnly && pending > 0) {
    lines.add('الحوالات بانتظار التأكيد: $pending (غير محسوبة ضمن الدفعات)');
  }

  if (individual && currentBalance != null) {
    lines.add('— الرصيد الحالي للحساب (حتى اليوم، خارج نطاق فلتر الفترة) —');
    if (supplier) {
      lines.add(currentBalance > 0
          ? 'المستحق للمورد: ${money(currentBalance)}'
          : currentBalance < 0
              ? 'رصيد لنا لدى المورد: ${money(-currentBalance)}'
              : 'الحساب مسدّد بالكامل.');
    } else {
      lines.add(currentBalance > 0
          ? 'المبلغ المستحق على الزبون: ${money(currentBalance)}'
          : currentBalance < 0
              ? 'رصيد للزبون لدينا: ${money(-currentBalance)}'
              : 'حساب الزبون مسدّد بالكامل.');
    }
  } else if (!individual && groupOutstanding != null && groupOutstanding > 0) {
    lines.add('— الأرصدة الحالية (حتى اليوم، خارج نطاق فلتر الفترة) —');
    lines.add(supplier
        ? 'إجمالي المستحق للموردين: ${money(groupOutstanding)}'
        : 'إجمالي المبالغ المستحقة على الزبائن: ${money(groupOutstanding)}');
  }

  if (!supplier && collectionAccounts.isNotEmpty) {
    lines.addAll(collectionAccountLines(collectionAccounts));
  }

  if (pendingLocal > 0) {
    lines.add('تنبيه: توجد $pendingLocal حركة محلية بانتظار المزامنة؛ لا يشملها هذا الملخص.');
  }
  return lines.join('\n');
}
