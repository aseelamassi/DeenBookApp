import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../ui/widgets.dart';

class Receipts {
  static Future<void> draft(
    BuildContext context,
    String text,
    String phone,
  ) async {
    var number = digits(phone).replaceAll(RegExp(r'\D'), '');
    if (number.startsWith('00')) number = number.substring(2);
    if (number.startsWith('0') && number.length == 10) {
      number = '970${number.substring(1)}';
    }
    if (number.length >= 10 &&
        await launchUrl(
          Uri.https('wa.me', '/$number', {'text': text}),
          mode: LaunchMode.externalApplication,
        )) {
      return;
    }
    if (!context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  static Future<void> payment(
    BuildContext context,
    Json party,
    Json e,
    String shop,
  ) => draft(
    context,
    '$shop\n${e['pendingConfirmation'] == true ? 'حوالة بانتظار الوصول — ليست إيصال قبض' : 'تم تسجيل الدفعة'}\n${party['name']}\n${money(e['amount'])} · ${day(e['occurredAt'])}\nرقم الحركة: ${e['id']}',
    '${party['phone'] ?? ''}',
  );
  static Future<void> statement(
    BuildContext context,
    Json s,
    String shop,
  ) => draft(
    context,
    '$shop\nكشف حساب ${s['party']['name']}\nرصيد بداية الفترة: ${money(s['openingBalance'])}\n${(s['entries'] as List).map((e) => '${day(e['occurredAt'])} · ${kinds[e['kind']]} · ${money((e['amount'] as num) - (e['discount'] as num? ?? 0))}${e['pendingConfirmation'] == true ? ' (بانتظار التأكيد)' : ''}').join('\n')}\nرصيد نهاية الفترة: ${money(s['closingBalance'])}',
    '${s['party']['phone'] ?? ''}',
  );
  static Future<bool> confirmTransfer(BuildContext context, Json entry) async {
    if (!await confirm(
      context,
      'تأكيد وصول الحوالة',
      'هل وصلت حوالة ${money(entry['amount'])} فعلياً؟ بعد التأكيد تُحتسب في الحساب والمقبوضات.',
    )) {
      return false;
    }
    if (!context.mounted) return false;
    final session = Scope.of(context);
    try {
      await session.api.request(
        'POST',
        '/api/transactions/${entry['id']}/confirm',
      );
      session.changed();
      return true;
    } catch (e) {
      if (context.mounted) message(context, e);
      return false;
    }
  }
}
