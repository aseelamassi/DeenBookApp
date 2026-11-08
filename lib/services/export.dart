import 'dart:convert';

import 'package:flutter/material.dart'
    show BuildContext, DateTimeRange, RenderBox, Offset;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/ledger.dart';

class Exports {
  static String pdfMoney(dynamic value) => money(value).replaceAll('₪', 'شيكل');
  // Split long descriptions into continuation rows so a large invoice can span pages.
  static List<List<String>> printableRows(List<List<String>> rows) =>
      rows.expand((row) {
        if (row.isEmpty || row.last.length <= 180) return [row];
        final result = <List<String>>[];
        var text = row.last;
        while (text.isNotEmpty) {
          var cut = text.length > 180 ? 180 : text.length;
          if (cut < text.length) {
            final space = text.lastIndexOf(' ', cut);
            if (space > 90) cut = space;
          }
          result.add([
            ...List.generate(
              row.length - 1,
              (i) => result.isEmpty ? row[i] : '',
            ),
            text.substring(0, cut),
          ]);
          text = text.substring(cut).trimLeft();
        }
        return result;
      }).toList();
  static Future<Uint8List> document(
    String shop,
    String title,
    List<String> details,
    List<String> headers,
    List<List<String>> rows,
  ) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Bold.ttf'),
    );
    final pdf = pw.Document(title: title, author: shop);
    pdf.addPage(
      pw.MultiPage(
        maxPages: 1000,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        header: (c) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              shop,
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#242872'),
              ),
            ),
            pw.Text(title, style: const pw.TextStyle(fontSize: 14)),
            pw.Divider(),
          ],
        ),
        footer: (c) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('دفتر دين', style: const pw.TextStyle(fontSize: 9)),
              pw.Text(
                '${c.pageNumber} / ${c.pagesCount}',
                textDirection: pw.TextDirection.ltr,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
        build: (c) => [
          ...details.map(
            (line) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(line),
            ),
          ),
          pw.SizedBox(height: 16),
          if (rows.isEmpty)
            pw.Text('لا توجد حركات في هذه الفترة.')
          else
            pw.TableHelper.fromTextArray(
              columnWidths: {
                for (var i = 0; i < headers.length; i++)
                  i: pw.FlexColumnWidth(
                    headers.length >= 5 && i == 0 ? 2.4 : 1.2,
                  ),
              },
              headers: headers.reversed.toList(),
              data: printableRows(
                rows,
              ).map((r) => r.reversed.toList()).toList(),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#242872'),
              ),
              cellAlignment: pw.Alignment.centerRight,
              cellPadding: const pw.EdgeInsets.all(6),
              oddRowDecoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
              ),
            ),
        ],
      ),
    );
    return pdf.save();
  }

  static String rangeLabel(DateTimeRange? r) =>
      r == null ? 'جميع الفترات' : 'الفترة: ${day(r.start)} — ${day(r.end)}';
  static Future<Uint8List> statementBytes(
    String shop,
    Json s, {
    DateTimeRange? range,
  }) => document(
    shop,
    'كشف حساب: ${s['party']['name']}',
    [
      rangeLabel(range),
      'رصيد بداية الفترة: ${pdfMoney(s['openingBalance'])}',
      'رصيد نهاية الفترة: ${pdfMoney(s['closingBalance'])}',
    ],
    ['التاريخ', 'الحركة', 'الصافي', 'دفع فوري', 'الرصيد بعدها', 'الوصف'],
    runningStatement(s)
        .map(
          (e) => [
            day(e['occurredAt']),
            kinds[e['kind']] ?? 'حركة',
            pdfMoney((e['amount'] as num) - (e['discount'] as num? ?? 0)),
            pdfMoney(e['paidNow']),
            pdfMoney(e['balanceAfter']),
            entryDescription(e).replaceAll('₪', 'شيكل'),
          ],
        )
        .toList(),
  );
  static Future<void> statement(
    String shop,
    Json s, {
    DateTimeRange? range,
  }) async {
    final bytes = await statementBytes(shop, s, range: range);
    await Printing.layoutPdf(
      name: 'DeenBook-statement.pdf',
      onLayout: (_) => Future.value(bytes),
    );
  }

  static Future<void> history(
    String shop,
    List<Json> rows,
    Map<String, String> names,
    DateTimeRange? range,
    String? kind, {
    String? selectionLabel,
  }) async {
    final bytes = await document(
      shop,
      'سجل الحركات',
      [
        rangeLabel(range),
        kind == null ? 'كل الحركات' : kinds[kind]!,
        if (selectionLabel?.isNotEmpty == true) selectionLabel!,
      ],
      ['التاريخ', 'الحساب', 'الحركة', 'المبلغ', 'الوصف'],
      rows
          .map(
            (e) => [
              day(e['occurredAt']),
              names[e['partyId']] ?? '',
              kinds[e['kind']] ?? 'حركة',
              pdfMoney((e['amount'] as num) - (e['discount'] as num? ?? 0)),
              entryDescription(e).replaceAll('₪', 'شيكل'),
            ],
          )
          .toList(),
    );
    await Printing.layoutPdf(
      name: 'DeenBook-history.pdf',
      onLayout: (_) => Future.value(bytes),
    );
  }

  static Future<void> report(
    String shop,
    Json data,
    DateTimeRange range,
  ) async {
    final s = data['summary'], c = data['cash'];
    final bytes = await document(
      shop,
      'تقرير المحل',
      [rangeLabel(range)],
      ['البيان', 'القيمة'],
      [
        ['المقبوضات — كل الوسائل', pdfMoney(s['received'])],
        ['المدفوعات — كل الوسائل', pdfMoney(s['paid'])],
        ['نقد وارد من الزبائن', pdfMoney(c['customerCashIn'])],
        ['نقد مدفوع للموردين', pdfMoney(c['supplierCashOut'])],
        ['صافي النقد في الفترة', pdfMoney(c['netCash'])],
        ['الذمم الحالية على الزبائن', pdfMoney(s['receivables'])],
        ['الذمم الحالية للموردين', pdfMoney(s['payables'])],
        ['ــــــــــــ تفاصيل المشتريات ــــــــــــ', ''],
        for (final row in (data['purchases']['items'] as List))
          [
            '${row['partyName']} · ${day(row['entry']['occurredAt'])}',
            [
              'قيمة بعد الخصم: ${pdfMoney((row['entry']['amount'] as num) - (row['entry']['discount'] as num? ?? 0))}',
              'مدفوع: ${pdfMoney(row['entry']['paidNow'])}',
              if ('${row['entry']['counterpartyName'] ?? ''}'.trim().isNotEmpty)
                'اللي إجا اشترى: ${row['entry']['counterpartyName']}',
              if ((row['entry']['items'] as List? ?? []).isNotEmpty)
                'الأصناف: ${(row['entry']['items'] as List).map((x) => '${x['name']} × ${x['quantity']} ${x['unit']}').join('، ')}',
              if ('${row['entry']['note'] ?? ''}'.trim().isNotEmpty)
                'ملاحظات: ${row['entry']['note']}',
            ].join(' | '),
          ],
        if (data['purchases']['truncated'] == true)
          ['تنبيه', 'النتائج تتجاوز 5000 حركة؛ اختر فترة أقصر'],
      ],
    );
    await Printing.layoutPdf(
      name: 'DeenBook-report.pdf',
      onLayout: (_) => Future.value(bytes),
    );
  }

  static String csvCell(String text) {
    final safe = RegExp(r'^[\s]*[=+@-]').hasMatch(text) ? "'$text" : text;
    return '"${safe.replaceAll('"', '""')}"';
  }

  static String historyCsvText(List<Json> rows, Map<String, String> names) =>
      '\uFEFF${[
        ['التاريخ', 'الحساب', 'الحركة', 'المبلغ بعد الخصم', 'حالة الحوالة', 'الوصف'].map(csvCell).join(','),
        ...rows.map((e) => [csvCell(day(e['occurredAt'])), csvCell(names[e['partyId']] ?? ''), csvCell(kinds[e['kind']] ?? 'حركة'), decimalMoney(amountCents(e['amount']) - amountCents(e['discount'])), csvCell(e['pendingConfirmation'] == true ? 'بانتظار التأكيد — غير محتسبة' : 'مسجّلة'), csvCell(entryDescription(e))].join(',')),
      ].join('\r\n')}';
  static Future<void> historyCsv(
    BuildContext context,
    List<Json> rows,
    Map<String, String> names,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(historyCsvText(rows, names))),
            mimeType: 'text/csv',
          ),
        ],
        fileNameOverrides: ['DeenBook-history.csv'],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  static Future<void> backup(Json data, BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(
              utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
            ),
            mimeType: 'application/json',
          ),
        ],
        fileNameOverrides: [
          'DeenBook-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json',
        ],
        sharePositionOrigin: origin,
      ),
    );
  }
}
