import 'package:intl/intl.dart';

String digits(String s) {
  const arabic = '٠١٢٣٤٥٦٧٨٩', persian = '۰۱۲۳۴۵۶۷۸۹';
  for (var i = 0; i < 10; i++) {
    s = s.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
  }
  return s;
}

String? phoneNumber(String raw) {
  var s = digits(raw).replaceAll(RegExp(r'[\s()\-]'), '');
  if (s.startsWith('00')) s = '+${s.substring(2)}';
  if (s.startsWith('+970') || s.startsWith('+972')) s = s.substring(4);
  if (s.startsWith('0')) s = s.substring(1);
  return RegExp(r'^5[69]\d{7}$').hasMatch(s) ? '+970$s' : null;
}

int? cents(String text, {bool signed = false}) {
  final s = digits(text.trim()).replaceAll('٫', '.');
  if (!RegExp(
    signed ? r'^-?\d+(\.\d{1,2})?$' : r'^\d+(\.\d{1,2})?$',
  ).hasMatch(s)) {
    return null;
  }
  final parts = s.replaceFirst('-', '').split('.');
  final value = int.tryParse(parts.first);
  if (value == null || value > 999999999) return null;
  final result =
      value * 100 +
      (parts.length == 2 ? int.parse(parts.last.padRight(2, '0')) : 0);
  if (result > 99999999900) return null;
  return s.startsWith('-') ? -result : result;
}

String money(dynamic n) =>
    '${NumberFormat('#,##0.00', 'en').format((n as num?) ?? 0)} ₪';
String day(dynamic s) {
  final d = DateTime.tryParse('$s');
  return d == null ? '—' : DateFormat('dd/MM/yyyy').format(d.toLocal());
}

Map<String, dynamic> period(DateTime start, DateTime end) => {
  'from': DateTime(
    start.year,
    start.month,
    start.day,
  ).toUtc().toIso8601String(),
  'to': DateTime(end.year, end.month, end.day + 1).toUtc().toIso8601String(),
};
const methods = {
  'Cash': 'نقداً',
  'JawwalPay': 'جوال باي',
  'PalPay': 'بال باي',
  'Bank': 'تحويل بنكي',
};
const kinds = {
  'Debt': 'دين',
  'Purchase': 'مشتريات',
  'Payment': 'دفعة',
  'Return': 'مرتجع',
};
String customerBalanceStatus(num balance) => balance < 0
    ? 'له رصيد'
    : balance > 0 ? 'عليه دين' : 'خالص';

String balanceLabel(Map<String, dynamic> p) {
  final balance = (p['balance'] as num?) ?? 0;
  if (balance == 0) return 'الحساب مسدّد';
  if (p['kind'] == 'Supplier') {
    return balance > 0 ? 'مستحق للمورد' : 'رصيد لدى المورد';
  }
  return balance > 0 ? 'مستحق على الزبون' : 'رصيد للزبون';
}
