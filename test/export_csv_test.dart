import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/services/export.dart';

void main() {
  test('Arabic CSV preserves cents, newlines and pending status', () {
    final text = Exports.historyCsvText(
      [
        {
          'partyId': 'p',
          'kind': 'Payment',
          'amount': 125.50,
          'discount': 0,
          'occurredAt': '2026-11-04',
          'note': 'سطر "أول"\nثانٍ',
          'pendingConfirmation': true,
        },
      ],
      {'p': 'أحمد'},
    );
    expect(text.startsWith('\uFEFF'), isTrue);
    expect(text, contains(',125.50,'));
    expect(text, contains('سطر ""أول""\nثانٍ'));
    expect(text, contains('بانتظار التأكيد — غير محتسبة'));
    expect(text, contains('أحمد'));
  });
  test('CSV text cells cannot become spreadsheet formulas', () {
    for (final value in ['=SUM(A1:A2)', '+123', '-cmd', '@name', ' \t=1']) {
      expect(Exports.csvCell(value).startsWith('"\''), isTrue);
    }
    expect(Exports.csvCell('متجر, "جديد"'), '"متجر, ""جديد"""');
  });
}
