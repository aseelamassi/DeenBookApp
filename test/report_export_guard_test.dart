import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/services/report_export_guard.dart';
import 'package:deenbook/services/export.dart';

void main() {
  test('a local outbox does not disable a successfully loaded report', () {
    expect(ReportExportGuard.available(
      loading: false, exporting: false, error: null,
    ), isTrue);
    expect(ReportExportGuard.available(
      loading: true, exporting: false, error: null,
    ), isFalse);
    expect(ReportExportGuard.available(
      loading: false, exporting: true, error: null,
    ), isFalse);
    expect(ReportExportGuard.available(
      loading: false, exporting: false, error: 'error',
    ), isFalse);
  });

  test('CSV makes pending local movements explicit and does not add them as transactions', () {
    final originalRow = <String, dynamic>{
      'partyId': 'p-1',
      'kind': 'Purchase',
      'amount': 270,
      'discount': 0,
      'occurredAt': '2026-11-13T10:00:00Z',
      'note': '1 كرتونة زيت',
      'pendingConfirmation': false,
    };
    final csv = Exports.historyCsvText(
      [originalRow],
      {'p-1': 'مورد'},
      pendingLocal: 6,
    );
    expect(csv.startsWith('\uFEFF'), isTrue);
    expect(csv, contains('6 حركة محفوظة على الجهاز'));
    expect(csv, contains('غير مشمولة'));
    expect(csv, contains('مورد'));
    expect(csv, contains('270.00'));
    expect(csv.split('\r\n').length, 3); // header, warning, one server row
  });
}
