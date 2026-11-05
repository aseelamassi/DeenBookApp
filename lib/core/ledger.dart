import 'api.dart';
import 'format.dart';

int amountCents(dynamic value) => ((value as num? ?? 0) * 100).round();
String decimalMoney(int value) => (value / 100).toStringAsFixed(2);
String quantityText(int value) =>
    (value / 1000).toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
int? quantityMillis(String raw) {
  var text = raw.trim().replaceAll('٫', '.');
  const digits = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  for (var i = 0; i < 10; i++) {
    text = text.replaceAll(digits[i], '$i').replaceAll(persian[i], '$i');
  }
  if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(text)) return null;
  final n = double.tryParse(text);
  return n == null || n <= 0 || n > 999999 ? null : (n * 1000).round();
}

class InvoiceLine {
  const InvoiceLine({
    required this.id,
    required this.name,
    required this.unit,
    required this.price,
    required this.quantity,
  });
  final String id, name, unit;
  final int price, quantity;
  int get total => (price * quantity + 500) ~/ 1000;
  InvoiceLine withQuantity(int value) => InvoiceLine(
    id: id,
    name: name,
    unit: unit,
    price: price,
    quantity: value,
  );
  factory InvoiceLine.product(Json p, bool purchase) => InvoiceLine(
    id: p['id'],
    name: p['name'],
    unit: p['unit'],
    price: amountCents(p[purchase ? 'purchasePrice' : 'salePrice']),
    quantity: 1000,
  );
  factory InvoiceLine.fromJson(Json p) => InvoiceLine(
    id: p['productId'],
    name: p['name'],
    unit: p['unit'],
    price: amountCents(p['unitPrice']),
    quantity: ((p['quantity'] as num) * 1000).round(),
  );
  Json toJson() => {
    'productId': id,
    'name': name,
    'unit': unit,
    'unitPrice': price / 100,
    'quantity': quantity / 1000,
    'total': total / 100,
  };
}

int effectivePayment(int requested, int handed, bool keepChange) =>
    keepChange && handed > requested ? handed : requested;
List<Json> runningStatement(Json statement) {
  var balance = amountCents(statement['openingBalance']);
  return (statement['entries'] as List).map((raw) {
    final entry = Map<String, dynamic>.from(raw);
    balance += amountCents(entry['delta']);
    return {...entry, 'balanceAfter': balance / 100};
  }).toList();
}

String entryDescription(Json e) => [
  if (e['pendingConfirmation'] == true) 'بانتظار وصول الحوالة — لم تُحتسب دفعة',
  if ((e['counterpartyName'] ?? '').toString().isNotEmpty)
    'المستلم / الدافع: ${e['counterpartyName']}',
  if (amountCents(e['discount']) > 0) 'خصم: ${money(e['discount'])}',
  if ((e['note'] ?? '').toString().isNotEmpty) '${e['note']}',
  for (final p in (e['items'] as List? ?? []))
    '${p['name']} · ${quantityText(((p['quantity'] as num) * 1000).round())} ${p['unit']} · ${money(p['total'])}',
  if ((e['createdByName'] ?? '').toString().isNotEmpty)
    'سجّلها: ${e['createdByName']}',
].join('\n');

// Summary of filtered statement entries; integer cents and confirmed payments only.
Json historyTotals(List<Json> entries, {required bool supplier}) {
  var invoices = 0, paid = 0, pending = 0;
  for (final e in entries) {
    if (e['pendingConfirmation'] == true) {
      pending++;
      continue;
    }
    if (e['kind'] == 'Debt' || e['kind'] == 'Purchase') {
      invoices += amountCents(e['amount']) - amountCents(e['discount']);
      paid += amountCents(e['paidNow']);
    } else if (e['kind'] == 'Payment') {
      paid += amountCents(e['amount']);
    }
  }
  return {
    'invoices': invoices / 100,
    'received': supplier ? 0 : paid / 100,
    'paid': supplier ? paid / 100 : 0,
    'pendingCount': pending,
  };
}
