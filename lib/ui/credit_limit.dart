import 'package:flutter/material.dart';
import '../core/credit_limit.dart';
import '../core/format.dart';
import 'theme.dart';
import 'design.dart';
import 'widgets.dart';

const creditRose = Color(0xFFBE123C);
const creditDarkRed = Color(0xFF881337);
const creditRosePale = Color(0xFFFFF1F2);

class CreditLimitGauge extends StatelessWidget {
  const CreditLimitGauge({
    super.key,
    required this.balance,
    required this.creditLimit,
    this.compact = false,
    this.showUnlimited = false,
  });
  final num balance;
  final dynamic creditLimit;
  final bool compact;
  final bool showUnlimited;

  @override
  Widget build(BuildContext context) {
    final status = creditLimitStatus(balance, creditLimit);
    if (status.limit == null) {
      return showUnlimited
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(status.label, style: appText(11, color: muted)),
            )
          : const SizedBox.shrink();
    }
    final alert = status.needsWarning;
    final color = status.level == CreditLimitLevel.exceeded
        ? creditDarkRed
        : alert ? creditRose : orange;
    return Padding(
      padding: EdgeInsets.only(top: compact ? 6 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Compact customer cards already show the warning in their status chip.
          if (alert && !compact)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(status.label, style: appText(11, weight: FontWeight.w900, color: color)),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: compact ? 5 : 8,
              value: status.progress,
              color: color,
              backgroundColor: const Color(0xFFE9EAF2),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'السقف: ${displayMoney(status.used)} / ${displayMoney(status.limit!)} · '
            '${status.excess > 0 ? 'تجاوز: ${displayMoney(status.excess)}' : 'متبقي: ${displayMoney(status.remaining)}'} · ${status.percent}%',
            style: appText(compact ? 9 : 11, color: alert ? color : secondaryText),
          ),
        ],
      ),
    );
  }
}

/// Reusable value input. A blank field or 0 means unlimited.
class CreditLimitPicker extends StatefulWidget {
  const CreditLimitPicker({super.key, required this.controller});
  final TextEditingController controller;

  @override
  State<CreditLimitPicker> createState() => _CreditLimitPickerState();
}

class _CreditLimitPickerState extends State<CreditLimitPicker> {
  static const values = [0, 200, 300, 500, 1000];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  void _refresh() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = num.tryParse(widget.controller.text.trim()) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('🛡️ سقف الدين المسموح للزبون (اختياري)',
            style: appText(12, weight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final value in values)
              ChoiceChip(
                label: Text(value == 0 ? 'بلا سقف (مفتوح)' : '$value ₪'),
                selected: current == value,
                onSelected: (_) => widget.controller.text = value == 0 ? '' : '$value',
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: widget.controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'سقف مخصص بالشيكل (اتركه فارغًا لحساب مفتوح)',
          ),
          validator: (value) {
            if ((value ?? '').trim().isEmpty) return null;
            final amount = cents(value!);
            return amount == null || amount < 0 ? 'أدخل سقفًا غير سالب بدقتين عشريتين' : null;
          },
        ),
      ],
    );
  }
}
