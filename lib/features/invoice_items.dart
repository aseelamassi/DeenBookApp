import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/format.dart';
import '../core/ledger.dart';
import '../ui/widgets.dart';
import 'catalog.dart';

class InvoiceItems extends StatelessWidget {
  const InvoiceItems({
    super.key,
    required this.lines,
    required this.purchase,
    required this.onChanged,
  });
  final List<InvoiceLine> lines;
  final bool purchase;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Heading(purchase ? 'أصناف البضاعة المستلمة وأسعارها' : 'أصناف الفاتورة'),
        Text(
          purchase
              ? 'أدخل الأصناف والكميات وسعر كل صنف. يمكنك الضغط على الصنف لتعديل الكمية بسرعة.'
              : 'أدخل الأصناف والكميات وسعر كل صنف داخل الفاتورة.',
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < lines.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(lines[i].name),
            subtitle: Text(
              '${quantityText(lines[i].quantity)} ${lines[i].unit} × ${money(lines[i].price / 100)}\n${money(lines[i].total / 100)}',
            ),
            trailing: IconButton(
              tooltip: 'حذف الصنف',
              icon: const Icon(Icons.close),
              onPressed: () {
                lines.removeAt(i);
                onChanged();
              },
            ),
            onTap: () async {
              final q = await showDialog<int>(
                context: context,
                builder: (_) => QuantityDialog(line: lines[i]),
              );
              if (q != null) {
                lines[i] = lines[i].withQuantity(q);
                onChanged();
              }
            },
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: Text(purchase ? 'إضافة صنف آخر للفاتورة' : 'إضافة صنف'),
          onPressed: () async {
            if (lines.length >= 100) {
              message(context, 'الحد الأقصى 100 صنف في الفاتورة.');
              return;
            }
            final p = await open<Json>(
              context,
              const CatalogScreen(mode: 'products', picker: true),
            );
            if (p == null || !context.mounted) return;
            final line = InvoiceLine.product(p, purchase);
            if (line.price <= 0) {
              message(
                context,
                'أضف سعر ${purchase ? 'الشراء' : 'البيع'} للصنف أولاً.',
              );
              return;
            }
            final q = await showDialog<int>(
              context: context,
              builder: (_) => QuantityDialog(line: line),
            );
            if (q != null) {
              lines.add(line.withQuantity(q));
              onChanged();
            }
          },
        ),
        Text(
          purchase
              ? 'يُحفظ سعر الشراء مع فاتورة المورد. تعديل سعر الصنف لاحقاً لا يغيّر الفاتورة المحفوظة.'
              : 'يُحفظ السعر مع الفاتورة. تعديل سعر الصنف لاحقاً لا يغيّرها.',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    ),
  );
}

class QuantityDialog extends StatefulWidget {
  const QuantityDialog({super.key, required this.line});
  final InvoiceLine line;
  @override
  State<QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<QuantityDialog> {
  late final quantity = TextEditingController(
    text: quantityText(widget.line.quantity),
  );
  final value = TextEditingController();
  String? error;
  @override
  void dispose() {
    quantity.dispose();
    value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = quantityMillis(quantity.text);
    return AlertDialog(
      title: Text(widget.line.name),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${money(widget.line.price / 100)} / ${widget.line.unit}'),
            TextField(
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'الكمية — ${widget.line.unit}',
                errorText: error,
              ),
              onChanged: (_) => setState(() {}),
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final n in [250, 500, 1000])
                  ActionChip(
                    label: Text(quantityText(n)),
                    onPressed: () =>
                        setState(() => quantity.text = quantityText(n)),
                  ),
              ],
            ),
            TextField(
              controller: value,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'أو احسب الكمية من مبلغ — شيكل',
              ),
              onChanged: (v) {
                final n = cents(v);
                if (n != null && n > 0 && widget.line.price > 0) {
                  setState(
                    () => quantity.text = quantityText(
                      (n * 1000 / widget.line.price).round(),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            Text(
              'الإجمالي الفعلي: ${money(q == null ? 0 : widget.line.withQuantity(q).total / 100)}',
            ),
            const Text(
              'تُقرّب الكمية لأقرب 0.001. راجع الإجمالي قبل الإضافة.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            if (q == null || widget.line.withQuantity(q).total <= 0) {
              setState(() => error = 'أدخل كمية موجبة حتى 3 منازل عشرية');
              return;
            }
            Navigator.pop(context, q);
          },
          child: const Text('اعتماد الكمية'),
        ),
      ],
    );
  }
}
