import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import '../core/ledger.dart';
import '../ui/design.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

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
  static const _quickTemplates = [
    {'name': 'شوال أرز 25 كجم', 'unit': 'شوال'},
    {'name': 'كرتونة زيت ذرة', 'unit': 'كرتونة'},
    {'name': 'طرد سكر', 'unit': 'طرد'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.lines.isEmpty) {
        _addEmptyLine();
      }
    });
  }

  void _addEmptyLine({String name = '', String unit = 'كرتونة'}) {
    if (widget.lines.length >= 100) {
      message(context, 'الحد الأقصى للفاتورة 100 صنف.');
      return;
    }
    final id = const Uuid().v4();
    widget.lines.add(
      InvoiceLine(
        id: id,
        name: name,
        unit: unit,
        price: 0,
        quantity: 1000,
      ),
    );
    widget.onPackCountChanged(id, 12);
    widget.onChanged();
    setState(() {});
  }

  void _addTemplate(String name, String unit) {
    final emptyIndex = widget.lines.indexWhere((line) => line.name.trim().isEmpty);
    if (emptyIndex >= 0) {
      final line = widget.lines[emptyIndex];
      widget.lines[emptyIndex] = line.withName(name).withUnit(unit);
      widget.onPackCountChanged(line.id, 12);
      widget.onChanged();
      setState(() {});
      return;
    }
    _addEmptyLine(name: name, unit: unit);
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
            'أدخل أصناف الفاتورة يدويًا. هذه الصفحة مستقلة عن قائمة أصناف المحل، وأسعارها أسعار جملة للمورد فقط.',
            style: appText(10, color: secondaryText),
          ),
          const SizedBox(height: 10),
          Text('إضافة سريعة من الأصناف المتكررة (اختصار للإدراج):',
              style: appText(11, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _quickTemplates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, index) {
                final item = _quickTemplates[index];
                return ActionChip(
                  label: Text('+ ${item['name']}'),
                  onPressed: () => _addTemplate(item['name']!, item['unit']!),
                );
              },
            ),
          ),
          for (var i = 0; i < widget.lines.length; i++) ...[
            const SizedBox(height: 10),
            _SupplierLineCard(
              key: ValueKey('supplier-line-${widget.lines[i].id}'),
              line: widget.lines[i],
              index: i,
              initialPackCount: widget.packCounts[widget.lines[i].id] ?? 12,
              onPackCountChanged: (n) => widget.onPackCountChanged(widget.lines[i].id, n),
              onEdit: (edited) {
                final index = widget.lines.indexWhere((p) => p.id == edited.id);
                if (index < 0) return;
                widget.lines[index] = edited;
                widget.onChanged();
              },
              onDelete: () {
                final removedId = widget.lines[i].id;
                widget.lines.removeWhere((p) => p.id == removedId);
                widget.packCounts.remove(removedId);
                widget.onChanged();
                setState(() {});
                if (widget.lines.isEmpty) {
                  _addEmptyLine();
                }
              },
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _addEmptyLine,
            icon: const Icon(Icons.add),
            label: const Text('إضافة صنف آخر للفاتورة'),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'لن تتم إضافة هذه الأصناف إلى قائمة أصناف المحل من هذه الصفحة. تُحفظ فقط داخل فاتورة المورد وتظهر بالتفصيل في سجل المورد.',
              style: appText(10, color: secondaryText),
            ),
          ),
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
  static const units = ['كرتونة', 'شوال', 'طرد', 'صندوق', 'كيلو', 'قطعة'];
  late final TextEditingController _name;
  late final TextEditingController _qty;
  late final TextEditingController _price;
  late final TextEditingController _packsInput;
  late int _packs;
  late String _unit;

  bool get _packageUnit => const {'كرتونة', 'شوال', 'طرد', 'صندوق'}.contains(_unit);

  @override
  void initState() {
    super.initState();
    _unit = widget.line.unit.isEmpty ? 'كرتونة' : widget.line.unit;
    _packs = widget.initialPackCount;
    _name = TextEditingController(text: widget.line.name);
    _qty = TextEditingController(text: quantityText(widget.line.quantity));
    _price = TextEditingController(text: widget.line.price > 0 ? decimalMoney(widget.line.price) : '');
    _packsInput = TextEditingController(text: '$_packs');
  }

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _price.dispose();
    _packsInput.dispose();
    super.dispose();
  }

  void _emit() {
    final q = quantityMillis(_qty.text) ?? widget.line.quantity;
    final p = cents(_price.text) ?? 0;
    widget.onEdit(
      widget.line
          .withName(_name.text.trim())
          .withUnit(_unit)
          .withQuantity(q)
          .withPrice(p),
    );
  }

  void _setQuantity(int quantity) {
    if (quantity <= 0 || quantity > 999999000) return;
    _qty.text = quantityText(quantity);
    _emit();
  }

  void _setPacks(int packs) {
    if (packs < 1 || packs > 10000) return;
    setState(() {
      _packs = packs;
      _packsInput.text = '$packs';
    });
    widget.onPackCountChanged(packs);
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line
        .withName(_name.text.trim())
        .withUnit(_unit)
        .withQuantity(quantityMillis(_qty.text) ?? widget.line.quantity)
        .withPrice(cents(_price.text) ?? 0);
    final subtotal = line.total;
    final pieceCost = _packageUnit && line.price > 0 && _packs > 0
        ? money(line.price / _packs / 100)
        : null;

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
              Expanded(
                child: TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'اسم الصنف'),
                  onChanged: (_) => _emit(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: DropdownButtonFormField<String>(
                  value: _unit,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الوحدة'),
                  items: units
                      .map((unit) => DropdownMenuItem(value: unit, child: Text(unit)))
                      .toList(),
                  onChanged: (unit) {
                    if (unit == null) return;
                    setState(() => _unit = unit);
                    _emit();
                  },
                ),
              ),
              IconButton(
                tooltip: 'حذف الصنف',
                onPressed: widget.onDelete,
                icon: const Icon(Icons.close, color: Color(0xFFC24154)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('الكمية ($_unit)', style: appText(10, color: secondaryText)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'زيادة',
                          onPressed: () => _setQuantity((quantityMillis(_qty.text) ?? 1000) + 1000),
                          icon: const Icon(Icons.add, size: 18),
                        ),
                        Expanded(
                          child: TextFormField(
                            controller: _qty,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(),
                            onChanged: (_) => setState(_emit),
                          ),
                        ),
                        IconButton(
                          tooltip: 'نقصان',
                          onPressed: () => _setQuantity((quantityMillis(_qty.text) ?? 1000) - 1000),
                          icon: const Icon(Icons.remove, size: 18),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('سعر $_unit (₪)', style: appText(10, color: secondaryText)),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _price,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(),
                      onChanged: (_) => setState(_emit),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('المجموع', style: appText(10, color: secondaryText)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1E5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        money(subtotal / 100),
                        textAlign: TextAlign.center,
                        style: appText(12, weight: FontWeight.w900, color: orange),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_packageUnit) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text('عدد العبوات بال$_unit:', style: appText(12, weight: FontWeight.w800)),
                ),
                SizedBox(
                  width: 72,
                  child: TextFormField(
                    controller: _packsInput,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(),
                    onChanged: (value) {
                      final next = int.tryParse(value.trim());
                      if (next != null) _setPacks(next);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final n in [6, 12, 24, 48])
                  ChoiceChip(
                    label: Text('$n'),
                    selected: _packs == n,
                    onSelected: (_) => _setPacks(n),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F8EE),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  pieceCost == null ? 'أدخل السعر والعدد' : 'للعبوة: $pieceCost',
                  style: appText(11, color: green, weight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
