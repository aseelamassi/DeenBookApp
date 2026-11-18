import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:deenbook/core/format.dart';
import 'package:deenbook/features/support_screen.dart';
import 'package:deenbook/services/export.dart';
import 'package:deenbook/ui/widgets.dart';

void main() {
  test('timestamps show the recorded local date and 24-hour time', () {
    expect(dateTimeStamp(DateTime(2026, 11, 18, 9, 45)), '18/11/2026 — 09:45');
    final remote = DateTime.parse('2026-11-18T09:45:00Z');
    expect(
      dateTimeStamp('2026-11-18T09:45:00Z'),
      DateFormat('dd/MM/yyyy — HH:mm').format(remote.toLocal()),
    );
    // Do not manufacture midnight for legacy records that store only dates.
    expect(dateTimeStamp('2026-11-18'), '18/11/2026');
    expect(dateTimeStamp(null), '—');
  });

  test('CSV includes the time in the transaction timestamp column', () {
    final csv = Exports.historyCsvText([
      {
        'partyId': 'abc',
        'kind': 'Payment',
        'amount': 18.0,
        'discount': 0,
        'occurredAt': DateTime(2026, 11, 18, 9, 45).toIso8601String(),
      },
    ], {'abc': 'زبون تجريبي'});
    expect(csv, contains('التاريخ والوقت'));
    expect(csv, contains('18/11/2026 — 09:45'));
    expect(csv, contains('زبون تجريبي'));
  });

  test('support contact opens the requested phone and WhatsApp number', () {
    expect(technicalSupportName, 'لؤي أبو زعنونة');
    expect(technicalSupportPhone, '+972594301646');
    expect(technicalSupportCallUri.scheme, 'tel');
    expect(technicalSupportCallUri.path, technicalSupportPhone);
    expect(technicalSupportWhatsAppUri.host, 'wa.me');
    expect(technicalSupportWhatsAppUri.path, '/972594301646');
  });

  testWidgets('movement card shows date and time', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: entryTile({
          'kind': 'Payment',
          'amount': 10,
          'discount': 0,
          'occurredAt': DateTime(2026, 11, 18, 9, 45).toIso8601String(),
        }),
      ),
    ));
    expect(find.textContaining('18/11/2026 — 09:45'), findsOneWidget);
  });

  testWidgets('support page contains working call and chat actions', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TechnicalSupportScreen()));
    expect(find.text('الدعم الفني'), findsOneWidget);
    expect(find.text('لؤي أبو زعنونة'), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      '+972594301646',
    );
    expect(find.text('اتصال هاتفي'), findsOneWidget);
    expect(find.text('إرسال رسالة واتساب'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'اتصال هاتفي')).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'إرسال رسالة واتساب')).onPressed, isNotNull);
  });
}
