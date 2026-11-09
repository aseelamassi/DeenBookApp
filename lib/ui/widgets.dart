import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/ledger.dart';
import 'theme.dart';
import 'design.dart';

class Width extends StatelessWidget {
  const Width({super.key, required this.child, this.max = 480});
  final Widget child;
  final double max;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: max),
      child: child,
    ),
  );
}

class Surface extends StatelessWidget {
  const Surface({super.key, required this.child, this.color = Colors.white});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Material(
      color: color,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE9EAF3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(width: double.infinity, child: child),
      ),
    ),
  );
}

class Heading extends StatelessWidget {
  const Heading(this.text, {super.key, this.action});
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?action,
      ],
    ),
  );
}

class Empty extends StatelessWidget {
  const Empty(
    this.title,
    this.message, {
    super.key,
    this.action,
    this.icon = Icons.auto_stories_outlined,
  });
  final String title, message;
  final Widget? action;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Surface(
    child: Column(
      children: [
        const SizedBox(height: 16),
        Icon(icon, size: 44, color: muted),
        const SizedBox(height: 14),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted),
        ),
        const SizedBox(height: 16),
        ?action,
      ],
    ),
  );
}

class BusyButton extends StatelessWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.background,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final Color? background;
  @override
  Widget build(BuildContext context) => FilledButton(
    style: background == null
        ? null
        : FilledButton.styleFrom(
            backgroundColor: background,
            foregroundColor: Colors.white,
          ),
    onPressed: busy ? null : onPressed,
    child: busy
        ? const SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(label, textAlign: TextAlign.center)),
            ],
          ),
  );
}

class Remote extends StatefulWidget {
  const Remote({super.key, required this.load, required this.builder});
  final Future<Json> Function() load;
  final Widget Function(Json) builder;
  @override
  State<Remote> createState() => _RemoteState();
}

class _RemoteState extends State<Remote> {
  late Future<Json> future;
  @override
  void initState() {
    super.initState();
    future = widget.load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: future,
    builder: (c, s) {
      if (s.connectionState != ConnectionState.done) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(36),
            child: CircularProgressIndicator(),
          ),
        );
      }
      if (s.hasError) {
        return Empty(
          'تعذّر تحميل البيانات',
          '${s.error}',
          icon: Icons.cloud_off_outlined,
          action: OutlinedButton(
            onPressed: () => setState(() => future = widget.load()),
            child: const Text('إعادة المحاولة'),
          ),
        );
      }
      return widget.builder(s.data!);
    },
  );
}

Widget field(
  TextEditingController controller,
  String label, {
  bool required = false,
  int max = 160,
  TextInputType? keyboard,
  String? Function(String?)? validator,
  int lines = 1,
  bool enabled = true,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: TextFormField(
    controller: controller,
    enabled: enabled,
    keyboardType: keyboard,
    maxLines: lines,
    maxLength: max,
    decoration: InputDecoration(labelText: label, counterText: ''),
    validator:
        validator ??
        (required
            ? (v) => v == null || v.trim().isEmpty ? 'هذا الحقل مطلوب' : null
            : null),
  ),
);
String displayMoney(dynamic value) => money(value).replaceFirst('.00', '');
Widget amount(dynamic value, {Color color = navy, double size = 24}) =>
    Text.rich(
      TextSpan(
        children: [
          TextSpan(text: displayMoney(value).replaceFirst(' ₪', '')),
          TextSpan(
            text: ' ₪',
            style: TextStyle(fontSize: size * .65, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      textDirection: TextDirection.rtl,
      style: appText(size, color: color, weight: FontWeight.w900, height: 1.2),
    );
Widget compactAmount(dynamic value, {double size = 17}) => ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 112),
  child: FittedBox(
    fit: BoxFit.scaleDown,
    child: amount(value, size: size),
  ),
);

Widget metric(String label, dynamic value, {Color color = navy}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(label, style: const TextStyle(color: muted, fontSize: 12)),
    const SizedBox(height: 6),
    FittedBox(child: amount(value, color: color)),
  ],
);
Widget partyTile(Json p, VoidCallback onTap) => Card(
  elevation: 0,
  margin: const EdgeInsets.only(bottom: 10),
  child: ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    onTap: onTap,
    leading: CircleAvatar(
      backgroundColor: navy.withValues(alpha: .07),
      child: Text((p['name'] as String? ?? '؟').characters.first),
    ),
    title: Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      balanceLabel(p),
      style: const TextStyle(color: muted, fontSize: 12),
    ),
    trailing: compactAmount(((p['balance'] as num?) ?? 0).abs()),
  ),
);
Widget entryTile(Json e, {String? name, VoidCallback? onConfirm, VoidCallback? onVoid}) {
  final pending = e['pendingConfirmation'] == true;
  final value = ((e['amount'] as num?) ?? 0) - ((e['discount'] as num?) ?? 0);
  final negative = ['Payment', 'Return'].contains(e['kind']);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name ?? kinds[e['kind']] ?? 'حركة',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${kinds[e['kind']] ?? ''} · ${day(e['occurredAt'])}',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: FittedBox(
                child: amount(
                  negative ? -value : value,
                  size: 14,
                  color: negative ? green : orange,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (e['kind'] == 'Payment' || amountCents(e['paidNow']) > 0)
          Text(
            methods[e['method']] ?? 'وسيلة قديمة',
            style: appText(10, color: muted),
          ),
        if ((e['note'] ?? '').toString().isNotEmpty)
          Text('${e['note']}', style: appText(11, color: secondaryText)),
        if ((e['counterpartyName'] ?? '').toString().isNotEmpty)
          Text(
            '${e['kind'] == 'Payment' && e['method'] != 'Cash' ? 'اسم صاحب الحوالة' : e['kind'] == 'Payment' ? 'الدافع / المستلم' : 'مستلم البضاعة'}: ${e['counterpartyName']}',
            style: const TextStyle(fontSize: 12),
          ),
        for (final p in (e['items'] as List? ?? []))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${p['name']} · ${quantityText(((p['quantity'] as num) * 1000).round())} ${p['unit']} · ${money(p['total'])}',
              style: const TextStyle(fontSize: 12, color: muted),
            ),
          ),
        if (amountCents(e['discount']) > 0)
          Text(
            'الخصم: ${money(e['discount'])}',
            style: const TextStyle(fontSize: 12),
          ),
        if (amountCents(e['paidNow']) > 0)
          Text(
            'دفع فوري: ${money(e['paidNow'])}',
            style: const TextStyle(fontSize: 12),
          ),
        if ((e['createdByName'] ?? '').toString().isNotEmpty)
          Text(
            'سجّلها: ${e['createdByName']}',
            style: const TextStyle(fontSize: 11, color: muted),
          ),
        if (e['balanceAfter'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'الرصيد بعدها: ${money(e['balanceAfter'])}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        if (onVoid != null) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onVoid,
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('شطب الحركة'),
            ),
          ),
        ],
        if (pending) ...[
          const SizedBox(height: 8),
          const Text(
            'بانتظار وصول الحوالة — لم تُحتسب دفعة',
            style: TextStyle(color: Color(0xFF8B5800), fontSize: 12),
          ),
          if (onConfirm != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: onConfirm,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('تأكيد الوصول'),
              ),
            ),
        ],
      ],
    ),
  );
}

void message(BuildContext context, Object text) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text('$text')));
Future<T?> open<T>(BuildContext context, Widget screen) {
  if (screen is ModalForm) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      clipBehavior: Clip.antiAlias,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(c).height * .78,
          child: screen,
        ),
      ),
    );
  }
  return Navigator.of(
    context,
  ).push<T>(MaterialPageRoute(builder: (_) => screen));
}

Future<bool> confirm(BuildContext context, String title, String text) =>
    showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    ).then((v) => v ?? false);
