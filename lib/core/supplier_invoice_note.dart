import 'format.dart';
import 'ledger.dart';

/// A readable invoice description. Invoice items remain the authoritative
/// structured snapshots; this text helps humans identify a paper invoice.
/// Trim only at a complete line boundary, never silently truncate a name.
String supplierInvoiceDescription({
  required String invoiceNumber,
  required List<InvoiceLine> lines,
  required Map<String, int> packCounts,
  int maxLength = 2000,
}) {
  final header = invoiceNumber.trim().isEmpty
      ? 'فاتورة بضاعة مورد'
      : 'فاتورة (#${invoiceNumber.trim()})';
  if (lines.isEmpty) return header;
  final parts = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final package = const {'كرتونة', 'صندوق', 'شوال', 'طرد'}.contains(line.unit);
    final packCount = packCounts[line.id] ?? 12;
    final price = '${money(line.price / 100)} / ${line.unit}';
    final detail = package
        ? '، $packCount عبوة، تكلفة العبوة: ${money(line.price / packCount / 100)}'
        : '';
    final part = '${quantityText(line.quantity)} ${line.unit} ${line.name} '
        '(السعر: $price، المجموع: ${money(line.total / 100)}$detail)';
    final remaining = lines.length - i - 1;
    final suffix = remaining > 0 ? '؛ +$remaining صنف آخر (تفاصيله محفوظة)' : '';
    final attempt = '$header: ${[...parts, part].join('؛ ')}$suffix';
    if (attempt.length > maxLength) {
      if (parts.isEmpty) return '$header: تفاصيل الأصناف محفوظة في سجل الفاتورة';
      return '$header: ${parts.join('؛ ')}؛ +${lines.length - i} صنف آخر (تفاصيله محفوظة)';
    }
    parts.add(part);
  }
  return '$header: ${parts.join('؛ ')}';
}
