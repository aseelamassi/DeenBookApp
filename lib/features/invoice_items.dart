import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/ledger.dart';
import '../core/session.dart';
import '../core/weight_pricing.dart';
import '../core/weight_entry_validation.dart';
import '../ui/widgets.dart';
import '../ui/design.dart';
import 'catalog.dart';

/// Customer invoice items are selected inline. Supplier invoices have their
/// own independent, manually entered wholesale editor.
class InvoiceItems extends StatefulWidget {
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
  State<InvoiceItems> createState() => _InvoiceItemsState();
}

class _InvoiceItemsState extends State<InvoiceItems> {
  final search = TextEditingController();
  Timer? debounce;
  List<Json> suggested = [];
  List<String> categories = [];
  String? category;
  int revision = 0;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    if (!widget.purchase) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadCategories();
        _search();
      });
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final res = await Scope.of(context).api.get('/api/products/categories');
      if (mounted) {
        setState(() => categories = (res['items'] as List? ?? [])
            .map((e) => '$e')
            .where((e) => e.isNotEmpty)
            .toList());
      }
    } catch (_) {
      // Existing products still appear in search when categories are offline.
    }
  }

  Future<void> _search() async {
    final id = ++revision;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = await Scope.of(context).api.get('/api/products', query: {
        'search': search.text.trim(),
        if (category != null) 'category': category,
        'page': 1,
        'size': 30,
      });
      if (mounted && id == revision) {
        setState(() => suggested = (res['items'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList());
      }
    } catch (_) {
      if (mounted && id == revision) {
        setState(() => error = 'تعذّر تحميل أصناف هذا القسم؛ اعرض الأصناف المحفوظة عند توفرها.');
      }
    } finally {
      if (mounted && id == revision) setState(() => loading = false);
    }
  }

  Future<void> _choose(Json product) async {
    if (widget.lines.length >= 100) {
      message(context, 'الحد الأقصى 100 صنف في الفاتورة.');
      return;
    }
    final line = InvoiceLine.product(product, false);
    if (line.price <= 0) {
      message(context, 'يجب تحديد سعر البيع للصنف أولاً.');
      return;
    }
    final gramsOrQuantity = await showDialog<Object>(
      context: context,
      builder: (_) => soldByWeight(product)
          ? WeightCalculatorDialog(line: line)
          : QuantityDialog(line: line),
    );
    if (gramsOrQuantity == null || !mounted) return;
    final selection = gramsOrQuantity is WeightSelection ? gramsOrQuantity : null;
    final q = selection?.grams ?? gramsOrQuantity as int;
    widget.lines.add(line.withQuantity(q).withPricingEntry(byAmount: selection?.byAmount ?? false));
    widget.onChanged();
    setState(() {});
  }

  Future<void> _edit(int index) async {
    final line = widget.lines[index];
    final qty = await showDialog<Object>(
      context: context,
      builder: (_) => line.unit == 'كغم'
          ? WeightCalculatorDialog(line: line)
          : QuantityDialog(line: line),
    );
    if (qty == null || !mounted) return;
    final selection = qty is WeightSelection ? qty : null;
    final q = selection?.grams ?? qty as int;
    widget.lines[index] = line.withQuantity(q).withPricingEntry(byAmount: selection?.byAmount ?? false);
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Heading('أصناف الفاتورة'),
        if (!widget.purchase) ...[
          TextField(
            controller: search,
            decoration: const InputDecoration(
              labelText: 'ابحث عن صنف لإضافته',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) {
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 280), _search);
            },
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 39,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                    label: const Text('الكل'),
                    selected: category == null,
                    onSelected: (_) {
                      setState(() => category = null);
                      _search();
                    },
                  ),
                ),
                for (final c in categories)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ChoiceChip(
                      label: Text(c),
                      selected: category == c,
                      onSelected: (_) {
                        setState(() => category = c);
                        _search();
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Text(error!, style: const TextStyle(fontSize: 11)),
          if (suggested.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 176),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F7FB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: suggested.length,
                itemBuilder: (c, i) {
                  final p = suggested[i];
                  return ListTile(
                    dense: true,
                    title: Text('${p['name']}'),
                    subtitle: Text('${p['category'] ?? 'عام'} · ${soldByWeight(p) ? '⚖️ بالوزن' : '📦 بالقطعة'} · ${money(p['salePrice'])} / ${soldByWeight(p) ? 'كيلو' : p['unit']}'),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () => _choose(p),
                  );
                },
              ),
            ),
        ],
        const SizedBox(height: 10),
        for (var i = 0; i < widget.lines.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(widget.lines[i].name),
            subtitle: Text(widget.lines[i].unit == 'كغم'
                ? '${weightLabel(widget.lines[i].quantity)} · ${money(widget.lines[i].price / 100)} / كيلو · ${money(widget.lines[i].total / 100)}'
                : '${quantityText(widget.lines[i].quantity)} ${widget.lines[i].unit} × ${money(widget.lines[i].price / 100)} = ${money(widget.lines[i].total / 100)}'),
            trailing: IconButton(
              tooltip: 'حذف الصنف',
              icon: const Icon(Icons.close),
              onPressed: () {
                widget.lines.removeAt(i);
                widget.onChanged();
                setState(() {});
              },
            ),
            onTap: () => _edit(i),
          ),
        if (widget.purchase)
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('إضافة صنف'),
            onPressed: () async {
              final p = await open<Json>(
                context,
                const CatalogScreen(mode: 'products', picker: true),
              );
              if (p != null && context.mounted) _choose(p);
            },
          ),
        const Text(
          'يُحفظ السعر والكمية في الحركة كما كانا وقت البيع؛ تعديل سعر الصنف لاحقًا لا يغيّرها.',
          style: TextStyle(fontSize: 11),
        ),
      ],
    ),
  );
}

class WeightSelection {
  const WeightSelection(this.grams, this.byAmount);
  final int grams;
  final bool byAmount;
}

class WeightCalculatorDialog extends StatefulWidget {
  const WeightCalculatorDialog({super.key, required this.line});
  final InvoiceLine line;

  @override
  State<WeightCalculatorDialog> createState() => _WeightCalculatorDialogState();
}

class _WeightCalculatorDialogState extends State<WeightCalculatorDialog> {
  late final weight = TextEditingController(text: '${widget.line.quantity}');
  final amount = TextEditingController();
  bool byAmount = false;
  bool inKilos = false;

  WeightEntryResult get result => validateWeightEntry(
        pricePerKgCents: widget.line.price,
        byAmount: byAmount,
        inKilos: inKilos,
        weightText: weight.text,
        amountText: amount.text,
      );

  @override
  void dispose() {
    weight.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calculation = result;
    final q = calculation.grams;
    final total = calculation.totalCents;
    final requested = calculation.requestedCents;
    return AlertDialog(
      title: Text('⚖️ ${widget.line.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('سعر الكيلو: ${money(widget.line.price / 100)}'),
            const SizedBox(height: 12),
            Segments<bool>(
              items: const {false: 'أدخل الوزن', true: 'أدخل المبلغ'},
              selected: byAmount,
              onSelected: (v) => setState(() => byAmount = v),
            ),
            const SizedBox(height: 14),
            if (!byAmount) ...[
              Wrap(
                spacing: 6,
                children: [
                  for (final g in [250, 500, 1000])
                    ActionChip(
                      label: Text(g == 250 ? 'ربع كيلو' : g == 500 ? 'نصف كيلو' : '1 كيلو'),
                      onPressed: () => setState(() {
                        inKilos = false;
                        weight.text = '$g';
                      }),
                    ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: weight,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: inKilos ? 'الوزن بالكيلو' : 'الوزن بالغرام',
                        helperText: 'الحد الأقصى 100 كغم للعملية الواحدة',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      if (inKilos) {
                        final g = quantityMillis(weight.text);
                        if (g != null) weight.text = '$g';
                      } else {
                        final g = int.tryParse(digits(weight.text));
                        if (g != null) weight.text = quantityText(g);
                      }
                      inKilos = !inKilos;
                    }),
                    child: Text(inKilos ? 'كغم' : 'غرام'),
                  ),
                ],
              ),
            ] else ...[
              Wrap(
                spacing: 6,
                children: [
                  for (final n in [5, 10, 15, 20])
                    ActionChip(
                      label: Text('بـ $n ₪'),
                      onPressed: () => setState(() => amount.text = '$n'),
                    ),
                ],
              ),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'مبلغ آخر (₪)',
                  helperText: 'الحد الأقصى 10,000 ₪ للعملية الواحدة',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F6EC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                !calculation.canSubmit
                    ? '⚖️ الوزن: 0 غرام — السعر: ${money(0)}'
                    : '⚖️ الوزن المطلوب على الميزان: ${weightLabel(q)} — السعر الفعلي: ${money(total / 100)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (calculation.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  calculation.error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            if (calculation.canSubmit && requested != null && requested != total)
              Text(
                'المبلغ المطلوب: ${money(requested / 100)}؛ الفرق ناتج عن التقريب لأقرب غرام، وسيُحفظ السعر الفعلي.',
                style: const TextStyle(fontSize: 11),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: calculation.canSubmit
              ? () => Navigator.pop(context, WeightSelection(q, byAmount))
              : null,
          child: const Text('إضافة للفاتورة'),
        ),
      ],
    );
  }
}

class QuantityDialog extends StatefulWidget {
  const QuantityDialog({super.key, required this.line});
  final InvoiceLine line;
  @override
  State<QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<QuantityDialog> {
  late final quantity = TextEditingController(text: quantityText(widget.line.quantity));
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'الكمية — ${widget.line.unit}', errorText: error),
              onChanged: (_) => setState(() {}),
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final n in [1000, 2000, 3000])
                  ActionChip(
                    label: Text(quantityText(n)),
                    onPressed: () => setState(() => quantity.text = quantityText(n)),
                  ),
              ],
            ),
            TextField(
              controller: value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'أو احسب العدد من مبلغ — شيكل'),
              onChanged: (v) {
                final n = cents(v);
                if (n != null && n > 0 && widget.line.price > 0) {
                  setState(() => quantity.text = quantityText((n * 1000 / widget.line.price).round()));
                }
              },
            ),
            const SizedBox(height: 12),
            Text('الإجمالي: ${money(q == null ? 0 : widget.line.withQuantity(q).total / 100)}'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            if (q == null || widget.line.withQuantity(q).total <= 0) {
              setState(() => error = 'أدخل كمية صحيحة');
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
