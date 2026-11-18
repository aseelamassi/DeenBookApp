import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/design.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

const technicalSupportName = 'لؤي أبو زعنونة';
const technicalSupportPhone = '+972594301646';

Uri get technicalSupportCallUri => Uri(
  scheme: 'tel',
  path: technicalSupportPhone,
);

Uri get technicalSupportWhatsAppUri => Uri.https(
  'wa.me',
  '/${technicalSupportPhone.substring(1)}',
  {'text': 'مرحباً، أحتاج إلى دعم فني بخصوص تطبيق دفتر دين.'},
);

class TechnicalSupportScreen extends StatelessWidget {
  const TechnicalSupportScreen({super.key});

  Future<void> _openLink(BuildContext context, Uri uri) async {
    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } catch (_) {
      // A device may not have a calling app or may block external links.
    }
    if (context.mounted) {
      message(context, 'تعذّر فتح التطبيق المطلوب. يمكنك نسخ الرقم والتواصل يدويًا.');
    }
  }

  Future<void> _copyPhone(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: technicalSupportPhone));
    if (context.mounted) message(context, 'تم نسخ رقم الدعم الفني');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الدعم الفني')),
    body: Width(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.support_agent_outlined, size: 48, color: navy),
                const SizedBox(height: 10),
                Text(
                  'تواصل مع الدعم الفني',
                  textAlign: TextAlign.center,
                  style: appText(18, weight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'للمساعدة في استخدام تطبيق دفتر دين أو الإبلاغ عن مشكلة.',
                  textAlign: TextAlign.center,
                  style: appText(12, color: secondaryText),
                ),
                const Divider(height: 30),
                Text('مسؤول الدعم الفني', style: appText(11, color: secondaryText)),
                const SizedBox(height: 4),
                Text(
                  technicalSupportName,
                  style: appText(17, weight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                Text('رقم الجوال وواتساب', style: appText(11, color: secondaryText)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        technicalSupportPhone,
                        textDirection: TextDirection.ltr,
                        style: appText(17, weight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'نسخ رقم الدعم',
                      icon: const Icon(Icons.copy_outlined),
                      onPressed: () => _copyPhone(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _openLink(context, technicalSupportCallUri),
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('اتصال هاتفي'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _openLink(context, technicalSupportWhatsAppUri),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('إرسال رسالة واتساب'),
                ),
                const SizedBox(height: 8),
                Text(
                  'يتم فتح تطبيق الاتصال أو واتساب على جهازك؛ الرسالة لا تُرسل تلقائيًا.',
                  textAlign: TextAlign.center,
                  style: appText(10, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
