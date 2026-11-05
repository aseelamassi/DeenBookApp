import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/ledger.dart';
import '../services/receipts.dart';
import '../core/session.dart';
import '../services/export.dart';
import '../ui/theme.dart';
import '../ui/design.dart';
import '../ui/widgets.dart';
import 'transaction.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.mode, this.picker = false});
  final String mode;
  final bool picker;
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final search = TextEditingController();
  Timer? debounce;
  List<Json> rows = [];
  Json? overview;
  int page = 0, total = 0, request = 0;
  bool busy = true, editProducts = false, showPriceNotice = true;
  String? error, filter, category;
  String sort = 'balance';
  String get sortLabel =>
      const {
        'balance': 'الأعلى رصيداً',
        'balanceAsc': 'الأقل رصيداً',
        'recent': 'آخر حركة',
        'name': 'الاسم',
      }[sort] ??
      'الأعلى رصيداً';
  bool get supplier => widget.mode == 'suppliers';
  bool get products => widget.mode == 'products';
  bool get modern => Scope.of(context).ledgerV2;
  String get title => products
      ? 'الأصناف'
      : supplier
      ? 'الموردون'
      : 'الزبائن';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    final id = ++request;
    setState(() {
      busy = true;
      error = null;
      if (!more) {
        rows = [];
        page = 0;
      }
    });
    try {
      final api = Scope.of(context).api;
      final data = await api.get(
        '/api/${widget.mode}',
        query: {
          'search': search.text.trim(),
          'sort': sort,
          if (filter != null) 'filter': filter,
          if (category != null) 'category': category,
          'page': page + 1,
          'size': 30,
        },
      );
      Json? stats = overview;
      if (modern && !more) {
        stats = products
            ? {
                'categories': (await api.get(
                  '/api/products/categories',
                ))['items'],
              }
            : await api.get('/api/${widget.mode}/overview');
      }
      if (!mounted || id != request) return;
      setState(() {
        rows = [
          ...rows,
          ...(data['items'] as List).map((e) => Map<String, dynamic>.from(e)),
        ];
        total = data['total'];
        page++;
        overview = stats;
      });
    } catch (e) {
      if (mounted && id == request) setState(() => error = '$e');
    } finally {
      if (mounted && id == request) setState(() => busy = false);
    }
  }

  Future<void> add() async {
    await open(
      context,
      products ? const ProductForm() : PartyForm(supplier: supplier),
    );
    if (mounted) load();
  }

  Future<void> transact(String kind, [Json? party]) async {
    await open(
      context,
      TransactionScreen(kind: kind, party: party, supplier: supplier),
    );
    if (mounted) load();
  }

  Future<void> details(Json p) async {
    if (widget.picker) {
      Navigator.pop(context, p);
      return;
    }
    await open(
      context,
      products
          ? ProductForm(existing: p)
          : supplier
          ? SupplierDetail(id: p['id'])
          : PartyDetail(id: p['id']),
    );
    if (mounted) load();
  }

  Widget accountCard(Json p) {
    final value = (p['balance'] as num? ?? 0);
    final credit = value < 0;
    final status = value == 0
        ? 'خالص ✓'
        : credit
        ? 'له رصيد'
        : supplier
        ? 'لهم مستحقات'
        : 'عليه دين';
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => details(p),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p['name']}${'${p['nickname'] ?? ''}'.isNotEmpty ? ' (${p['nickname']})' : ''}',
                        style: appText(14, weight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      if (!supplier)
                        SoftTag(
                          status,
                          color: credit ? green : orange,
                          background: credit
                              ? const Color(0xFFECFDF5)
                              : paleOrange,
                        ),
                      if ('${p['phone'] ?? ''}'.isNotEmpty)
                        Text(
                          '• ${p['phone']}',
                          style: appText(
                            11,
                            color: secondaryText,
                            weight: FontWeight.w600,
                          ),
                        ),
                      if ('${p[supplier ? 'category' : 'paymentSchedule'] ?? ''}'
                          .isNotEmpty)
                        Text(
                          '${p[supplier ? 'category' : 'paymentSchedule']}',
                          style: appText(11, color: secondaryText),
                        ),
                      if ('${p['lastNote'] ?? ''}'.isNotEmpty)
                        Text(
                          '${p['lastNote']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: appText(10, color: muted),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FB),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: lineColor),
                  ),
                  child: Column(
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 90),
                        child: FittedBox(
                          child: amount(
                            value.abs(),
                            size: 16,
                            color: credit ? green : orange,
                          ),
                        ),
                      ),
                      Text(status, style: appText(10, color: muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!widget.picker) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DesignButton(
                    supplier
                        ? 'فاتورة'
                        : credit
                        ? 'سحب من الرصيد'
                        : 'تسجيل دين',
                    icon: Icons.add,
                    height: 32,
                    background: paleOrange,
                    foreground: orange,
                    onTap: () => transact(supplier ? 'Purchase' : 'Debt', p),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: DesignButton(
                    supplier
                        ? 'سداد'
                        : credit
                        ? 'زيادة الرصيد'
                        : 'قبض دفعة',
                    icon: Icons.check,
                    height: 32,
                    onTap: () => transact('Payment', p),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: DesignButton(
                    supplier ? 'كشف المورد' : 'كشف الحساب',
                    height: 32,
                    background: const Color(0xFFF1F5F9),
                    foreground: secondaryText,
                    onTap: () async {
                      await open(context, PartyDetail(id: p['id']));
                      if (mounted) load();
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget header() => BrandCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                supplier
                    ? 'ذمم الموردين وفواتير البضائع'
                    : 'حسابات الزبائن والديون',
                style: appText(
                  16,
                  weight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (!widget.picker)
              DesignButton(
                supplier ? 'مورد' : 'زبون جديد',
                icon: Icons.add,
                height: 32,
                background: orange,
                foreground: Colors.white,
                onTap: add,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: .15)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          supplier
                              ? 'إجمالي المستحقات علينا للموردين'
                              : 'إجمالي الديون المستحقة لنا',
                          style: appText(11, color: Colors.white70),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          child: amount(
                            overview?['outstanding'] ?? 0,
                            size: 30,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (supplier)
                    const SoftTag(
                      'توريد بضائع الجملة',
                      color: Color(0xFFFED7AA),
                      background: Color(0xFF444574),
                    )
                  else
                    DesignButton(
                      'تسجيل بالصوت',
                      icon: Icons.mic_none,
                      height: 34,
                      background: Colors.white.withValues(alpha: .1),
                      foreground: Colors.white,
                      onTap: () =>
                          open(context, const TransactionScreen(voice: true)),
                    ),
                ],
              ),
              const Divider(color: Colors.white12, height: 22),
              Row(
                children: [
                  for (final stat
                      in supplier
                          ? [
                              ('لهم مستحقات', 'owing', const Color(0xFFFED7AA)),
                              ('حساب خالص', 'settled', const Color(0xFF6EE7B7)),
                              ('إجمالي الشركات', 'total', Colors.white),
                            ]
                          : [
                              ('عليهم دين', 'owing', const Color(0xFFFED7AA)),
                              ('لهم رصيد', 'credit', const Color(0xFF6EE7B7)),
                              ('حساب خالص', 'settled', Colors.white),
                            ])
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.symmetric(
                          vertical: 9,
                          horizontal: 4,
                        ),
                        decoration: BoxDecoration(
                          color: navy.withValues(alpha: .23),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            Text(
                              stat.$1,
                              style: appText(10, color: Colors.white70),
                            ),
                            Text(
                              '${overview?[stat.$2] ?? 0} ${supplier ? 'موردين' : 'زبائن'}',
                              textAlign: TextAlign.center,
                              style: appText(
                                11,
                                weight: FontWeight.w900,
                                color: stat.$3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (!widget.picker) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DesignButton(
                  supplier ? 'تسجيل فاتورة مورد' : 'تسجيل مشتريات (دين)',
                  icon: Icons.add,
                  height: 44,
                  background: orange,
                  foreground: Colors.white,
                  onTap: () => transact(supplier ? 'Purchase' : 'Debt'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DesignButton(
                  supplier ? 'سداد دفعة لمورد' : 'قبض دفعة / سداد',
                  icon: Icons.check,
                  height: 44,
                  background: Colors.white,
                  onTap: () => transact('Payment'),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
  Widget productCard(Json p) => Surface(
    child: InkWell(
      onTap: () => details(p),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: lavender,
              border: Border.all(color: const Color(0xFFD5DAF3)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: orange,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p['name']}',
                  style: appText(14, weight: FontWeight.w900),
                ),
                Text(
                  '${displayMoney(p['salePrice'])} / ${p['unit']}',
                  style: appText(12, color: navy, weight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!widget.picker)
            DesignButton(
              editProducts ? 'تعديل' : 'بيع بالدين',
              icon: editProducts ? Icons.edit_outlined : Icons.add,
              height: 32,
              border: true,
              onTap: () async {
                await open(
                  context,
                  editProducts
                      ? ProductForm(existing: p)
                      : TransactionScreen(initialProduct: p),
                );
                if (mounted) load();
              },
            ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: load,
      child: Width(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            if (!products)
              header()
            else
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: lavender,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: orange,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'قائمة الأصناف والأسعار',
                          style: appText(16, weight: FontWeight.w900),
                        ),
                        Text(
                          'أصناف المحل بالقطعة والوزن',
                          style: appText(11, color: muted),
                        ),
                      ],
                    ),
                  ),
                  if (!widget.picker) ...[
                    const SizedBox(width: 8),
                    DesignButton(
                      'صنف جديد',
                      icon: Icons.add,
                      background: orange,
                      foreground: Colors.white,
                      onTap: add,
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'خيارات الأصناف',
                      onSelected: (v) {
                        if (v == 'add') {
                          add();
                        } else {
                          setState(() => editProducts = !editProducts);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'add',
                          child: Text('إضافة صنف جديد'),
                        ),
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(
                            editProducts
                                ? 'إنهاء التعديل'
                                : 'تعديل الأصناف والأسعار',
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: search,
                    style: appText(12),
                    decoration: InputDecoration(
                      hintText: products
                          ? 'ابحث عن صنف بالاسم أو الوحدة…'
                          : supplier
                          ? 'ابحث باسم المورد أو صنف البضاعة…'
                          : 'ابحث بالاسم أو اللقب أو الهاتف…',
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 18,
                        color: muted,
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 34),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 10,
                      ),
                    ),
                    onChanged: (_) {
                      debounce?.cancel();
                      debounce = Timer(
                        const Duration(milliseconds: 350),
                        () => load(),
                      );
                    },
                  ),
                ),
                if (!products) ...[
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    tooltip: 'ترتيب حسب',
                    initialValue: sort,
                    onSelected: (v) {
                      setState(() => sort = v);
                      load();
                    },
                    itemBuilder: (_) =>
                        {
                              'balance': 'الأعلى رصيداً',
                              if (modern) 'balanceAsc': 'الأقل رصيداً',
                              if (modern) 'recent': 'آخر حركة',
                              'name': 'الاسم',
                            }.entries
                            .map(
                              (e) => PopupMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            )
                            .toList(),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFD5DAF3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.swap_vert, size: 14),
                          Text(
                            sort == 'balance'
                                ? (supplier ? 'الأعلى مستحقات' : 'الأعلى ديناً')
                                : sortLabel,
                            style: appText(10, weight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (!products && !supplier) ...[
              const SizedBox(height: 12),
              DesignChips<String?>(
                items: {
                  null: 'الكل ${overview?['total'] ?? 0}',
                  'debt': 'عليهم دين ${overview?['owing'] ?? 0}',
                  'credit': 'لهم رصيد ${overview?['credit'] ?? 0}',
                  'scheduled': 'بموعد محدد ${overview?['scheduled'] ?? 0}',
                  'settled': 'خالص ✓ ${overview?['settled'] ?? 0}',
                },
                selected: filter,
                onSelected: (v) {
                  setState(() => filter = v);
                  load();
                },
              ),
            ],
            if (products) ...[
              const SizedBox(height: 12),
              DesignChips<String?>(
                items: {
                  null: 'الكل',
                  for (final c in (overview?['categories'] as List? ?? []))
                    '$c': '$c',
                },
                selected: category,
                onSelected: (v) {
                  setState(() => category = v);
                  load();
                },
              ),
              if (showPriceNotice && !widget.picker) ...[
                const SizedBox(height: 14),
                Surface(
                  color: lavender,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 19,
                        color: secondaryText,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'قاعدة الأمان المالي وثبات القيود في دفتر دين:',
                              style: appText(11, weight: FontWeight.w800),
                            ),
                            Text(
                              'تعديل أسعار الأصناف أو حذفها لا يؤثر على المشتريات القائمة، ولا يغيّر أي فاتورة قديمة.',
                              style: appText(11, color: secondaryText),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'إخفاء التوضيح',
                        onPressed: () =>
                            setState(() => showPriceNotice = false),
                        icon: const Icon(Icons.close, size: 16, color: muted),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ],
            ],
            const SizedBox(height: 14),
            if (error != null)
              Empty(
                'تعذّر التحميل',
                error!,
                action: OutlinedButton(
                  onPressed: load,
                  child: const Text('حاول مجدداً'),
                ),
              ),
            if (!busy && rows.isEmpty && error == null)
              Empty(
                'لا توجد نتائج',
                search.text.isNotEmpty || filter != null || category != null
                    ? 'جرّب اسماً أو فلترًا آخر.'
                    : 'ابدأ بإضافة ${products
                          ? 'صنف'
                          : supplier
                          ? 'مورد'
                          : 'زبون'} جديد.',
                action: OutlinedButton(
                  onPressed: add,
                  child: const Text('إضافة الآن'),
                ),
              ),
            ...rows.map((p) => products ? productCard(p) : accountCard(p)),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!busy && rows.length < total)
              OutlinedButton(
                onPressed: () => load(more: true),
                child: Text('عرض المزيد (${rows.length} / $total)'),
              ),
          ],
        ),
      ),
    );
    return widget.picker
        ? Scaffold(
            appBar: AppBar(
              title: Text(
                'اختيار ${products
                    ? 'صنف'
                    : supplier
                    ? 'مورد'
                    : 'زبون'}',
              ),
            ),
            body: body,
          )
        : body;
  }
}

class PartyForm extends ModalForm {
  const PartyForm({super.key, required this.supplier, this.existing});
  final bool supplier;
  final Json? existing;
  @override
  State<PartyForm> createState() => _PartyFormState();
}

class _PartyFormState extends State<PartyForm> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  bool busy = false, credit = false, agreement = false;
  String? error;
  bool get modern => Scope.of(context).ledgerV2;
  @override
  void initState() {
    super.initState();
    for (final key in [
      'name',
      'phone',
      'nickname',
      'category',
      'representative',
      'deliveryDays',
      'paymentSchedule',
      'openingBalance',
      'alternatePhone',
      'alternateContact',
    ]) {
      fields[key] = TextEditingController(
        text:
            '${widget.existing?[key] ?? (key == 'openingBalance' ? '0' : '')}',
      );
    }
    credit = amountCents(widget.existing?['openingBalance']) < 0;
    fields['openingBalance']!.text = decimalMoney(
      amountCents(widget.existing?['openingBalance']).abs(),
    );
    agreement = fields['paymentSchedule']!.text.isNotEmpty;
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    final session = Scope.of(context);
    try {
      final body = <String, dynamic>{
        for (final e in fields.entries)
          if (modern || !['alternatePhone', 'alternateContact'].contains(e.key))
            e.key: e.value.text.trim(),
        'openingBalance':
            widget.existing?['openingBalance'] ??
            (cents(fields['openingBalance']!.text)! *
                (credit && !widget.supplier ? -1 : 1) /
                100),
        'paymentSchedule': agreement || widget.supplier
            ? fields['paymentSchedule']!.text.trim()
            : '',
        'acceptedMethods': widget.existing?['acceptedMethods'] ?? '',
      };
      await session.api.request(
        widget.existing == null ? 'POST' : 'PUT',
        widget.existing == null
            ? '/api/${widget.supplier ? 'suppliers' : 'customers'}'
            : '/api/parties/${widget.existing!['id']}',
        body: body,
      );
      session.changed();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FormSheetScaffold(
    title:
        '${widget.existing == null ? 'إضافة' : 'تعديل'} ${widget.supplier ? 'مورد' : 'زبون'}',
    body: Width(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'ابدأ بالاسم. يمكنك إكمال التفاصيل لاحقاً.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 20),
                field(
                  fields['name']!,
                  'الاسم',
                  validator: (v) => (v?.trim().length ?? 0) < 2
                      ? 'أدخل اسماً من حرفين على الأقل'
                      : null,
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: field(
                        fields[widget.supplier ? 'category' : 'nickname']!,
                        widget.supplier
                            ? 'نوع التوريد (اختياري)'
                            : 'اللقب (اختياري)',
                        max: widget.supplier ? 50 : 80,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: field(
                        fields['phone']!,
                        'رقم الجوال (اختياري)',
                        max: 30,
                        keyboard: TextInputType.phone,
                      ),
                    ),
                  ],
                ),
                if (modern && !widget.supplier) ...[
                  field(
                    fields['alternatePhone']!,
                    'رقم إضافي (اختياري)',
                    max: 30,
                    keyboard: TextInputType.phone,
                  ),
                  field(
                    fields['alternateContact']!,
                    'صاحب الرقم / صلة القرابة (اختياري)',
                    max: 80,
                  ),
                ],
                if (widget.existing == null) ...[
                  if (!widget.supplier)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('دين على الزبون'),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('رصيد للزبون'),
                          ),
                        ],
                        selected: {credit},
                        onSelectionChanged: (v) =>
                            setState(() => credit = v.first),
                      ),
                    ),
                  field(
                    fields['openingBalance']!,
                    'الرصيد الافتتاحي — شيكل',
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) => cents(v ?? '') == null
                        ? 'أدخل مبلغاً صحيحاً بدقتين عشريتين'
                        : null,
                  ),
                ],
                if (!widget.supplier) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('يوجد اتفاق على موعد الدفع'),
                    value: agreement,
                    onChanged: (v) => setState(() => agreement = v!),
                  ),
                  if (agreement) ...[
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final p in [
                          'أول كل شهر',
                          'كل خميس',
                          'منتصف الشهر',
                        ])
                          ActionChip(
                            label: Text(p),
                            onPressed: () =>
                                fields['paymentSchedule']!.text = p,
                          ),
                      ],
                    ),
                    field(
                      fields['paymentSchedule']!,
                      'موعد الدفع المتفق عليه',
                      required: true,
                      max: 120,
                    ),
                  ],
                ] else
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('تفاصيل إضافية (اختياري)'),
                    children: [
                      field(fields['representative']!, 'اسم المندوب', max: 120),
                      field(fields['deliveryDays']!, 'أيام التوريد', max: 100),
                      field(fields['paymentSchedule']!, 'موعد الدفع', max: 120),
                    ],
                  ),
                const SizedBox(height: 20),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
                BusyButton(
                  label: 'حفظ ${widget.supplier ? 'المورد' : 'الزبون'}',
                  onPressed: save,
                  busy: busy,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Supplier details are intentionally separate from customer statements.
/// This screen uses the existing party API and preserves transaction behavior.
class SupplierDetail extends StatefulWidget {
  const SupplierDetail({super.key, required this.id});
  final String id;

  @override
  State<SupplierDetail> createState() => _SupplierDetailState();
}

class _SupplierDetailState extends State<SupplierDetail> {
  Future<Json>? future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future ??= load();
  }

  Future<Json> load() => Scope.of(context).api.get('/api/parties/${widget.id}');

  void refresh() => setState(() => future = load());

  Future<void> action(Json supplier, String kind) async {
    await open(
      context,
      TransactionScreen(kind: kind, party: supplier, supplier: true),
    );
    if (mounted) refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('بيانات المورد')),
    body: FutureBuilder<Json>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Width(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Empty(
                'تعذّر تحميل بيانات المورد',
                '${snapshot.error}',
                action: OutlinedButton(
                  onPressed: refresh,
                  child: const Text('إعادة المحاولة'),
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final supplier = snapshot.data!;
        return Width(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Heading(
                      '${supplier['name']}',
                      action: IconButton(
                        tooltip: 'تعديل المورد',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          await open(
                            context,
                            PartyForm(supplier: true, existing: supplier),
                          );
                          if (mounted) refresh();
                        },
                      ),
                    ),
                    Text(
                      balanceLabel(supplier),
                      style: const TextStyle(color: muted),
                    ),
                    const SizedBox(height: 6),
                    amount(((supplier['balance'] as num?) ?? 0).abs()),
                    if ('${supplier['category'] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text('التصنيف: ${supplier['category']}'),
                      ),
                    if ('${supplier['phone'] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('${supplier['phone']}'),
                      ),
                    if ('${supplier['alternatePhone'] ?? ''}'.isNotEmpty)
                      Text(
                        '${supplier['alternateContact'] ?? 'هاتف إضافي'}: ${supplier['alternatePhone']}',
                      ),
                    if ('${supplier['deliveryDays'] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('التوريد: ${supplier['deliveryDays']}'),
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: BusyButton(
                      label: 'فاتورة',
                      background: orange,
                      onPressed: () => action(supplier, 'Purchase'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: BusyButton(
                      label: 'دفعة',
                      onPressed: () => action(supplier, 'Payment'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

class PartyDetail extends StatefulWidget {
  const PartyDetail({super.key, required this.id});
  final String id;
  @override
  State<PartyDetail> createState() => _PartyDetailState();
}

class _PartyDetailState extends State<PartyDetail> {
  Future<Json>? future;
  DateTimeRange? range;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future ??= load();
  }

  Future<Json> load() => Scope.of(context).api.get(
    '/api/parties/${widget.id}/statement',
    query: range == null ? null : period(range!.start, range!.end),
  );
  void refresh() => setState(() => future = load());
  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: future,
    builder: (c, s) {
      final ready = s.connectionState == ConnectionState.done && s.hasData;
      final data = s.data;
      return Scaffold(
        appBar: AppBar(
          title: const Text('كشف الحساب'),
          actions: [
            IconButton(
              tooltip: 'مشاركة كشف الحساب',
              onPressed: ready
                  ? () async {
                      try {
                        await Receipts.statement(
                          context,
                          data!,
                          Scope.of(context).shopName,
                        );
                      } catch (e) {
                        if (context.mounted) message(context, e);
                      }
                    }
                  : null,
              icon: const Icon(Icons.share_outlined),
            ),
            IconButton(
              tooltip: 'طباعة كشف الحساب',
              onPressed: ready
                  ? () async {
                      try {
                        await Exports.statement(
                          Scope.of(context).shopName,
                          data!,
                          range: range,
                        );
                      } catch (e) {
                        if (context.mounted) message(context, e);
                      }
                    }
                  : null,
              icon: const Icon(Icons.print_outlined),
            ),
          ],
        ),
        body: !ready
            ? s.hasError
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Empty(
                        'تعذّر التحميل',
                        '${s.error}',
                        action: OutlinedButton(
                          onPressed: refresh,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator())
            : Width(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Heading(
                            '${data!['party']['name']}',
                            action: IconButton(
                              tooltip: 'تعديل البطاقة',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () async {
                                try {
                                  final p = await Scope.of(
                                    context,
                                  ).api.get('/api/parties/${widget.id}');
                                  if (!context.mounted) return;
                                  await open(
                                    context,
                                    PartyForm(
                                      supplier: p['kind'] == 'Supplier',
                                      existing: p,
                                    ),
                                  );
                                  if (mounted) refresh();
                                } catch (e) {
                                  if (context.mounted) message(context, e);
                                }
                              },
                            ),
                          ),
                          Text(
                            balanceLabel(
                              Map<String, dynamic>.from(data['party']),
                            ),
                          ),
                          amount((data['party']['balance'] as num).abs()),
                          for (final key in ['phone', 'alternatePhone'])
                            if ('${data['party'][key] ?? ''}'.isNotEmpty)
                              TextButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(
                                      text: '${data['party'][key]}',
                                    ),
                                  );
                                  if (context.mounted) {
                                    message(context, 'تم نسخ الرقم');
                                  }
                                },
                                icon: const Icon(Icons.copy, size: 16),
                                label: Text(
                                  '${key == 'alternatePhone' ? '${data['party']['alternateContact'] ?? 'هاتف إضافي'}: ' : ''}${data['party'][key]}',
                                ),
                              ),
                          if ('${data['party']['paymentSchedule'] ?? ''}'
                              .isNotEmpty)
                            Text(
                              'اتفاق الدفع: ${data['party']['paymentSchedule']}',
                            ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final kind in [
                                data['party']['kind'] == 'Supplier'
                                    ? 'Purchase'
                                    : 'Debt',
                                'Payment',
                                'Return',
                              ])
                                OutlinedButton(
                                  onPressed: () async {
                                    try {
                                      final current = await Scope.of(
                                        context,
                                      ).api.get('/api/parties/${widget.id}');
                                      if (!context.mounted) return;
                                      await open(
                                        context,
                                        TransactionScreen(
                                          kind: kind,
                                          party: current,
                                        ),
                                      );
                                      if (mounted) refresh();
                                    } catch (e) {
                                      if (context.mounted) message(context, e);
                                    }
                                  },
                                  child: Text(kinds[kind]!),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            range == null
                                ? 'كل الحركات'
                                : '${day(range!.start)} — ${day(range!.end)}',
                          ),
                        ),
                        IconButton(
                          tooltip: 'الفترة',
                          onPressed: () async {
                            final r = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now(),
                              initialDateRange: range,
                            );
                            if (r != null) {
                              range = r;
                              refresh();
                            }
                          },
                          icon: const Icon(Icons.date_range),
                        ),
                        if (range != null)
                          IconButton(
                            tooltip: 'كل الفترات',
                            onPressed: () {
                              range = null;
                              refresh();
                            },
                            icon: const Icon(Icons.clear),
                          ),
                      ],
                    ),
                    Surface(
                      child: Row(
                        children: [
                          Expanded(
                            child: metric(
                              'رصيد أول الفترة',
                              data['openingBalance'],
                            ),
                          ),
                          Expanded(
                            child: metric(
                              'رصيد آخر الفترة',
                              data['closingBalance'],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if ((data['entries'] as List).isEmpty)
                      const Empty(
                        'لا توجد حركات',
                        'سجّل أول عملية ليبدأ كشف الحساب.',
                      )
                    else
                      Surface(
                        child: Column(
                          children: runningStatement(data).reversed
                              .map(
                                (e) => entryTile(
                                  e,
                                  onConfirm: () async {
                                    if (await Receipts.confirmTransfer(
                                          context,
                                          e,
                                        ) &&
                                        mounted) {
                                      refresh();
                                    }
                                  },
                                ),
                              )
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ),
      );
    },
  );
}

class ProductForm extends ModalForm {
  const ProductForm({super.key, this.existing});
  final Json? existing;
  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    for (final k in [
      'name',
      'unit',
      'category',
      'salePrice',
      'purchasePrice',
    ]) {
      fields[k] = TextEditingController(
        text:
            '${widget.existing?[k] ?? (k.endsWith('Price')
                    ? '0'
                    : k == 'category'
                    ? 'عام'
                    : k == 'unit'
                    ? 'قطعة'
                    : '')}',
      );
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final session = Scope.of(context);
      await session.api.request(
        widget.existing == null ? 'POST' : 'PUT',
        '/api/products${widget.existing == null ? '' : '/${widget.existing!['id']}'}',
        body: {
          for (final e in fields.entries)
            e.key: e.key.endsWith('Price')
                ? cents(e.value.text)! / 100
                : e.value.text.trim(),
        },
      );
      session.changed();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FormSheetScaffold(
    title: widget.existing == null ? 'إضافة صنف جديد' : 'تعديل الصنف',
    body: Width(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                field(fields['name']!, 'اسم الصنف', required: true),
                field(
                  fields['salePrice']!,
                  'سعر البيع — شيكل',
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) =>
                      cents(v ?? '') == null ? 'أدخل سعراً صحيحاً' : null,
                ),
                Text('وحدة البيع', style: appText(12, weight: FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final unit in ['قطعة', 'كغم', 'ربطة', 'كرتونة', 'لتر'])
                      DesignButton(
                        unit,
                        height: 34,
                        background: fields['unit']!.text == unit
                            ? navy
                            : canvas,
                        foreground: fields['unit']!.text == unit
                            ? Colors.white
                            : navy,
                        onTap: () =>
                            setState(() => fields['unit']!.text = unit),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  maintainState: true,
                  title: Text(
                    'تفاصيل إضافية (اختياري)',
                    style: appText(12, weight: FontWeight.w800),
                  ),
                  children: [
                    field(fields['unit']!, 'الوحدة', required: true, max: 30),
                    field(
                      fields['category']!,
                      'التصنيف',
                      required: true,
                      max: 60,
                    ),
                    field(
                      fields['purchasePrice']!,
                      'سعر الشراء — شيكل',
                      keyboard: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) =>
                          cents(v ?? '') == null ? 'أدخل سعراً صحيحاً' : null,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'تعديل الأسعار يخص الفواتير الجديدة. الفواتير المحفوظة تحتفظ بأسعارها.',
                  style: appText(11, color: muted),
                ),
                const SizedBox(height: 20),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
                BusyButton(label: 'حفظ الصنف', onPressed: save, busy: busy),
                if (widget.existing != null)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (!await confirm(
                              context,
                              'حذف الصنف',
                              'هل تريد حذف هذا الصنف؟',
                            )) {
                              return;
                            }
                            if (!context.mounted) return;
                            setState(() => busy = true);
                            try {
                              await Scope.of(context).api.request(
                                'DELETE',
                                '/api/products/${widget.existing!['id']}',
                              );
                              if (context.mounted) {
                                Scope.of(context).changed();
                                Navigator.pop(context, true);
                              }
                            } catch (e) {
                              if (mounted) setState(() => error = '$e');
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    child: const Text(
                      'حذف الصنف',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
