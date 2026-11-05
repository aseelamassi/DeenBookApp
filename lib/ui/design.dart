import 'package:flutter/material.dart';

import 'theme.dart';

class SoftTag extends StatelessWidget {
  const SoftTag(
    this.text, {
    super.key,
    this.color = navy,
    this.background = lavender,
  });
  final String text;
  final Color color, background;
  @override
  Widget build(BuildContext c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: appText(10, weight: FontWeight.w800, color: color),
    ),
  );
}

class DesignButton extends StatelessWidget {
  const DesignButton(
    this.label, {
    super.key,
    required this.onTap,
    this.background = lavender,
    this.foreground = navy,
    this.icon,
    this.height = 44,
    this.border = false,
  });
  final String label;
  final VoidCallback? onTap;
  final Color background, foreground;
  final IconData? icon;
  final double height;
  final bool border;
  @override
  Widget build(BuildContext c) => Material(
    color: background,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: border
          ? const BorderSide(color: Color(0xFFD5DAF3))
          : BorderSide.none,
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: appText(
                    12,
                    weight: FontWeight.w800,
                    color: onTap == null ? muted : foreground,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class DesignChips<T> extends StatelessWidget {
  const DesignChips({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });
  final Map<T, String> items;
  final T selected;
  final ValueChanged<T> onSelected;
  @override
  Widget build(BuildContext c) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: items.entries
          .map(
            (e) => Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: DesignButton(
                e.value,
                height: 32,
                background: selected == e.key ? navy : Colors.white,
                foreground: selected == e.key ? Colors.white : secondaryText,
                onTap: () => onSelected(e.key),
              ),
            ),
          )
          .toList(),
    ),
  );
}

class Segments<T> extends StatelessWidget {
  const Segments({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });
  final Map<T, String> items;
  final T selected;
  final ValueChanged<T> onSelected;
  @override
  Widget build(BuildContext c) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xFFE8EDF2),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: items.entries
          .map(
            (e) => Expanded(
              child: DesignButton(
                e.value,
                height: 36,
                background: selected == e.key
                    ? Colors.white
                    : Colors.transparent,
                foreground: selected == e.key ? navy : secondaryText,
                onTap: () => onSelected(e.key),
              ),
            ),
          )
          .toList(),
    ),
  );
}

class BrandCard extends StatelessWidget {
  const BrandCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext c) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: brandGradient,
      borderRadius: BorderRadius.circular(26),
      boxShadow: const [
        BoxShadow(
          color: Color(0x25242872),
          blurRadius: 6,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: child,
  );
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.back = false});
  final bool back;
  @override
  Widget build(BuildContext c) => Container(
    color: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    child: Row(
      children: [
        if (back)
          IconButton(
            onPressed: () => Navigator.maybePop(c),
            tooltip: 'رجوع',
            icon: const Icon(Icons.chevron_right),
          ),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: navy,
            borderRadius: BorderRadius.circular(17),
          ),
          child: const Icon(
            Icons.menu_book_outlined,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('دفتر دين', style: appText(16, weight: FontWeight.w900)),
              Text(
                'كل حساب إله مكان · دفتر محلك الإلكتروني',
                style: appText(11, color: muted, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

abstract class ModalForm extends StatefulWidget {
  const ModalForm({super.key});
}

class FormSheetScaffold extends StatelessWidget {
  const FormSheetScaffold({super.key, required this.title, required this.body});
  final String title;
  final Widget body;
  @override
  Widget build(BuildContext c) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      automaticallyImplyLeading: false,
      title: Text(title, style: appText(18, weight: FontWeight.w900)),
      actions: [
        IconButton(
          tooltip: 'إغلاق',
          onPressed: () => Navigator.maybePop(c),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
    body: body,
  );
}
