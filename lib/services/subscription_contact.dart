import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/widgets.dart';

const configuredSupportPhone = String.fromEnvironment('SUPPORT_PHONE');

String? normalizeSupportPhone(String raw) {
  var phone = raw.trim().replaceAll(RegExp(r'[\s()+-]'), '');
  if (phone.startsWith('00')) phone = phone.substring(2);
  return RegExp(r'^[1-9]\d{8,14}$').hasMatch(phone) ? phone : null;
}

bool get hasSupportContact =>
    normalizeSupportPhone(configuredSupportPhone) != null;

String subscriptionRequestText({
  required String shopName,
  required int months,
  String? phone,
  bool renewal = false,
}) {
  if (months != 1 && months != 3) throw ArgumentError.value(months, 'months');
  final duration = months == 1 ? 'شهر واحد' : 'ثلاثة أشهر';
  final amount = months == 1 ? 60 : 150;
  return [
    'مرحباً، أرغب ${renewal ? 'بتجديد الاشتراك' : 'بفتح حساب جديد'} لمحل ${shopName.trim()}.',
    if (phone?.trim().isNotEmpty == true) 'رقم الجوال: ${phone!.trim()}',
    'الخطة: $duration، بقيمة $amount شيكل.',
    'يرجى تزويدي بطريقة الدفع وخطوات ${renewal ? 'التجديد' : 'تفعيل الحساب'}.',
  ].join('\n');
}

Future<void> contact(
  BuildContext context,
  String text, {
  String supportPhone = configuredSupportPhone,
  Future<bool> Function(Uri)? launcher,
}) async {
  final phone = normalizeSupportPhone(supportPhone);
  var opened = false;
  if (phone != null) {
    try {
      final uri = Uri.https('wa.me', '/$phone', {'text': text});
      opened =
          await (launcher?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
    } catch (_) {
      // Opening another app may fail. No request has been sent to our API.
    }
  }
  if (!context.mounted) return;
  if (opened) {
    message(context, 'فُتح رابط واتساب. اضغط «إرسال» هناك لإكمال الطلب.');
    return;
  }
  final copy = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('لم يُرسل الطلب'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              phone == null
                  ? 'التواصل مع إدارة الخدمة غير متاح من التطبيق حالياً. يمكنك نسخ التفاصيل وإرسالها للإدارة عند التواصل معها.'
                  : 'تعذّر فتح واتساب. يمكنك نسخ التفاصيل وإرسالها إلى إدارة الخدمة.',
            ),
            if (phone != null) ...[
              const SizedBox(height: 12),
              SelectableText('+$phone', textDirection: TextDirection.ltr),
            ],
            const SizedBox(height: 16),
            SelectableText(text),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('إغلاق'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('نسخ التفاصيل'),
        ),
      ],
    ),
  );
  if (copy != true) return;
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      message(context, 'تم نسخ التفاصيل فقط؛ لم يُرسل الطلب.');
    }
  } catch (_) {
    if (context.mounted) message(context, 'تعذّر نسخ التفاصيل. حاول مجدداً.');
  }
}
