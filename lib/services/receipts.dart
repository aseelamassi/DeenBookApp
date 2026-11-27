import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api.dart';
import '../core/collection_accounts.dart';
import '../core/contact_phone.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../ui/widgets.dart';

class Receipts {
  static Future<void> draft(
    BuildContext context,
    String text,
    String phone,
  ) async {
    final uri = whatsappContactUri(phone, text);
    if (uri != null) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return;
        }
      } catch (_) {
        // A missing WhatsApp handler must not lose the statement text.
      }
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
    '$shop\n${e['pendingConfirmation'] == true ? 'حوالة بانتظار الوصول — ليست إيصال قبض' : 'تم تسجيل الدفعة'}\n${party['name']}\n${money(e['amount'])} · ${dateTimeStamp(e['occurredAt'])}\nرقم الحركة: ${e['id']}',
    '${party['phone'] ?? ''}',
  );
  static Future<void> statement(
    BuildContext context,
    Json s,
    String shop, {
    List<ShopCollectionAccount> collectionAccounts = const [],
  }) => draft(
    context,
    '$shop\nكشف حساب ${s['party']['name']}\n${s['offlinePartial']==true?'نسخة محلية غير مكتملة — الأرصدة قد تكون غير محدثة\n':''}رصيد بداية الفترة: ${money(s['openingBalance'])}\n${(s['entries'] as List).where((e) => e['voidedAt'] == null).map((e) => '${dateTimeStamp(e['occurredAt'])} · ${kinds[e['kind']]} · ${money((e['amount'] as num) - (e['discount'] as num? ?? 0))}${e['pendingConfirmation'] == true ? ' (بانتظار التأكيد)' : ''}').join('\n')}\nرصيد نهاية الفترة: ${money(s['closingBalance'])}${s['party']['kind'] == 'Customer' && collectionAccounts.isNotEmpty ? '\n${collectionAccountLines(collectionAccounts).join('\n')}' : ''}',
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
      final updated = await session.api.request(
        'POST',
        '/api/transactions/${entry['id']}/confirm',
      );
      if (updated is Map && updated['queued']==true) {
        entry['offlineLedgerAction']='confirm';
        await session.updatePending();
        session.changed();
        if (context.mounted) message(context,'حُفظ طلب التأكيد؛ سيُعتمد الرصيد بعد المزامنة.');
        return true;
      }
      // Make the confirmation visible in the current tile immediately.
      if (updated is Map) {
        entry.addAll(Map<String, dynamic>.from(updated));
      } else {
        entry['pendingConfirmation'] = false;
      }
      // Re-fetch balances and statements from the backend after confirmation.
      session.changed();
      return true;
    } catch (e) {
      if (context.mounted) message(context, e);
      return false;
    }
  }
}
