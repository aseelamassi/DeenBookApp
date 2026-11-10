import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/ledger.dart';
import '../core/session.dart';
import '../ui/design.dart';
import '../ui/party_lookup_field.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'catalog.dart';

/// Supplier invoice editor. It creates genuine LedgerItem snapshots, using
/// existing catalog product IDs and the /api/products endpoint. No unregistered
/// product name is ever sent as a fictional product ID.
class SupplierInvoiceItems extends StatefulWidget {
  const SupplierInvoiceItems({
    super.key,
    required this.lines,
    required this.onChanged,
    required this.packCounts,
    required this.onPackCountChanged,
  });

  final List<InvoiceLine> lines;
  final VoidCallback onChanged;
  final Map<String, int> packCounts;
  final void Function(String productId, int count) onPackCountChanged;

  @override
  State<SupplierInvoiceItems> createState() => _SupplierInvoiceItemsState();
}

class _SupplierInvoiceItemsState extends State<SupplierInvoiceItems> {
  int _searchRevision = 0;
  List<Json> _quickProducts = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadQuickProducts());
  }

  Future<void> _loadQuickProducts() async {
    try {
      final response = await Scope.of(context).api.get(
        '/api/products', query: {'page': 1, 'size': 8},
      );
      if (!mounted) return;
      setState(() {
        // Real catalog products only: never use the screenshot's example
        // prices as if they were the shop's actual prices.
        _quickProducts = (response['items'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((product) => (product['purchasePrice'] as num? ?? 0) > 0)
            .take(6).toList();
      });
    } catch (_) {
      // Catalog search remains available even when suggested items fail.
    }
  }

  void _choose(Json? product) {
    if (product == null) return;
    final id = '${product['id']}';
    if (widget.lines.length >= 100 &&
        !widget.lines.any((line) => line.id == id)) {
      message(context, 'الحد الأقصى للفاتورة 100 صنف.');
      return;
    }
    final existing = widget.lines.indexWhere((line) => line.id == id);
    if (existing >= 0) {
      final old = widget.lines[existing];
      widget.lines[existing] = old.withQuantity(old.quantity + 1000);
    } else {
      widget.lines.add(InvoiceLine.product(product, true));
    }
    setState(() => _searchRevision++);
    widget.onChanged();
  }

  Future<void> _addProduct() async {
    final created = await open<bool>(context, const ProductForm());
    if (created == true && mounted) {
      setState(() => _searchRevision++);
      message(context, 'تم حفظ الصنف. ابحث عن اسمه أعلاه لإضافته إلى الفاتورة.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.lines.length;
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'أصناف البضاعة المستلمة وأسعارها',
                  style: appText(13, weight: FontWeight.w900),
                ),
              ),
              SoftTag('$count أصناف'),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'ابحث عن الصنف، ثم حدّد الوحدة والكمية وسعر الشراء. تُحسب قيمة الفاتورة تلقائيًا.',
            style: appText(10, color: secondaryText),
          ),
          const SizedBox(height: 12),
          if (_quickProducts.isNotEmpty) ...[
            Text('إضافة سريعة من قائمة أصناف محلك',
              style: appText(11, weight: FontWeight.w800)),
            const SizedBox(height: 6),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _quickProducts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, index) {
                  final product = _quickProducts[index];
                  return ActionChip(
                    label: Text('+ ${product['name']} (${money(product['purchasePrice'])})'),
                    onPressed: () => _choose(product),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
          PartyLookupField(
            key: ValueKey('supplier-product-search-$_searchRevision'),
            label: 'الصنف',
            selected: null,
            search: (term) async {
              final response = await Scope.of(context).api.get(
                '/api/products',
                query: {'search': term, 'page': 1, 'size': 30},
              );
              return (response['items'] as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
            },
            onSelected: _choose,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _addProduct,
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('صنف جديد غير موجود في القائمة'),
            ),
          ),
          if (widget.lines.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: canvas,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'لم تُضف أصنافًا بعد. اختر صنفًا من نتائج البحث أو أضف صنفًا جديدًا.',
                style: appText(11, color: secondaryText),
              ),
            ),
          for (var i = 0; i < widget.lines.length; i++) ...[
            const SizedBox(height: 10),
            _SupplierLineCard(
              key: ValueKey('supplier-line-${widget.lines[i].id}'),
              line: widget.lines[i],
              index: i,
              initialPackCount: widget.packCounts[widget.lines[i].id] ?? 12,
              onPackCountChanged: (n) =>
                  widget.onPackCountChanged(widget.lines[i].id, n),
              onEdit: (edited) {
                final index = widget.lines.indexWhere((p) => p.id == edited.id);
                if (index < 0) return;
                widget.lines[index] = edited;
                widget.onChanged();
              },
              onDelete: () {
                final removedId = widget.lines[i].id;
                widget.lines.removeWhere((p) => p.id == removedId);
                widget.onChanged();
              },
            ),
          ],
          if (widget.lines.isNotEmpty) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => setState(() => _searchRevision++),
              icon: const Icon(Icons.add),
              label: const Text('إضافة صنف آخر للفاتورة'),
            ),
            const SizedBox(height: 8),
            Text(
              'أسعار وكميات الأصناف تُحفظ مع الفاتورة كنسخة تاريخية. لإنشاء صنف جديد استخدم «صنف جديد»؛ يُحفظ في قائمة المحل قبل اختياره.',
              style: appText(10, color: muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _SupplierLineCard extends StatefulWidget {
  const _SupplierLineCard({
    super.key,
    required this.line,
    required this.index,
    required this.initialPackCount,
    required this.onEdit,
    required this.onDelete,
    required this.onPackCountChanged,
  });
  final InvoiceLine line;
  final int index;
  final int initialPackCount;
  final ValueChanged<InvoiceLine> onEdit;
  final VoidCallback onDelete;
  final ValueChanged<int> onPackCountChanged;

  @override
  State<_SupplierLineCard> createState() => _SupplierLineCardState();
}

class _SupplierLineCardState extends State<_SupplierLineCard> {
  static const units = ['قطعة', 'كرتونة', 'شوال', 'طرد', 'صندوق', 'كيلو', 'كغم', 'ربطة', 'لتر'];
  late final TextEditingController _qty;
  late final TextEditingController _price;
  late int _packs;
  late String _unit;

  bool get _packageUnit =>
      const {'كرتونة', 'شوال', 'طرد', 'صندوق'}.contains(_unit);

  @override
  void initState() {
    super.initState();
    _unit = widget.line.unit;
    _packs = widget.initialPackCount;
    _qty = TextEditingController(text: quantityText(widget.line.quantity));
    _price = TextEditingController(text: decimalMoney(widget.line.price));
  }

  @override
  void didUpdateWidget(covariant _SupplierLineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.unit != widget.line.unit) _unit = widget.line.unit;
    if (oldWidget.line.quantity != widget.line.quantity &&
        quantityMillis(_qty.text) != widget.line.quantity) {
      _qty.text = quantityText(widget.line.quantity);
    }
    final expected = widget.line.price;
    if (oldWidget.line.price != widget.line.price &&
        cents(_price.text) != expected) {
      _price.text = decimalMoney(expected);
    }
  }

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  void _setQuantity(int quantity) {
    if (quantity <= 0 || quantity > 999999000) return;
    _qty.text = quantityText(quantity);
    widget.onEdit(widget.line.withQuantity(quantity));
  }

  void _setUnit(String unit) {
    if (_unit == unit) return;
    setState(() {
      _unit = unit;
      // Changing a wholesale unit must never silently convert a single-piece
      // price to an expensive carton price (or the reverse).
      _price.clear();
    });
    widget.onEdit(widget.line.withUnit(unit).withPrice(0));
  }

  void _setPacks(int packs) {
    if (packs < 1 || packs > 10000) return;
    setState(() => _packs = packs);
    widget.onPackCountChanged(packs);
    // Pack size affects the *displayed single-piece cost* only; it must not
    // change the paper invoice's wholesale unit price or total.
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final label = _packageUnit ? 'سعر $_unit (₪)' : 'سعر ${line.unit} (₪)';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: lineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SoftTag('${widget.index + 1}'),
              const SizedBox(width: 8),
              Expanded(child: Text(line.name, style: appText(12, weight: FontWeight.w900))),
              IconButton(
                tooltip: 'حذف الصنف من الفاتورة',
                onPressed: widget.onDelete,
                icon: const Icon(Icons.close, color: Color(0xFFC24154)),
              ),
            ],
          ),
          const SizedBox(height: 5),
          DropdownButtonFormField<String>(
            value: _unit,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'الوحدة'),
            items: {
              _unit,
              ...units,
            }.map((unit) => DropdownMenuItem(
                  value: unit,
                  child: Text(unit),
                )).toList(),
            onChanged: (unit) {
              if (unit != null) _setUnit(unit);
            },
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _qty,
                  key: ValueKey('supplier-quantity-${line.id}'),
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'الكمية'),
                  validator: (value) => quantityMillis(value ?? '') == null
                      ? 'أدخل كمية صحيحة' : null,
                  onChanged: (value) {
                    final n = quantityMillis(value);
                    if (n != null) widget.onEdit(line.withQuantity(n));
                  },
                ),
              ),
              const SizedBox(width: 7),
              Column(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'زيادة الكمية',
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: () => _setQuantity(line.quantity + 1000),
                  ),
                  IconButton(
                    tooltip: 'تقليل الكمية',
                    icon: const Icon(Icons.remove, size: 18),
                    onPressed: () => _setQuantity(line.quantity - 1000),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextFormField(
                  controller: _price,
                  key: ValueKey('supplier-unit-price-${line.id}'),
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: label),
                  validator: (value) {
                    final price = cents(value ?? '');
                    return price == null || price <= 0
                        ? 'أدخل سعرًا صحيحًا' : null;
                  },
                  onChanged: (value) {
                    final valueCents = cents(value);
                    if (valueCents != null && valueCents > 0) {
                      widget.onEdit(line.withPrice(valueCents));
                    }
                  },
                ),
              ),
            ],
          ),
          if (_packageUnit) ...[
            const SizedBox(height: 8),
            Text('عدد العبوات في $_unit', style: appText(11)),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final n in [6, 12, 24, 48])
                  ChoiceChip(
                    label: Text('$n'),
                    selected: _packs == n,
                    onSelected: (_) => _setPacks(n),
                  ),
                ActionChip(
                  label: Text('$_packs عبوة'),
                  avatar: const Icon(Icons.edit_outlined, size: 16),
                  onPressed: () async {
                    var typed = '$_packs';
                    final next = await showDialog<int>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text('عدد العبوات في $_unit'),
                        content: TextFormField(
                          initialValue: typed,
                          autofocus: true,
                          onChanged: (value) => typed = value,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: 'مثال: 20'),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
                          FilledButton(
                            onPressed: () => Navigator.pop(c, int.tryParse(typed.trim())),
                            child: const Text('تطبيق'),
                          ),
                        ],
                      ),
                    );
                    if (next != null && mounted) _setPacks(next);
                  },
                ),
              ],
            ),
            Text(
              line.price > 0
                  ? 'تكلفة العبوة الواحدة: ${money(line.price / _packs / 100)}'
                  : 'أدخل سعر $_unit لحساب تكلفة العبوة',
              style: appText(11, color: green, weight: FontWeight.w800),
            ),
          ],
          const Divider(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('مجموع الصنف', style: appText(11, color: secondaryText)),
              Text(money(line.total / 100), style: appText(13, color: orange, weight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }
}
