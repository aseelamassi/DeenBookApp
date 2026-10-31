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
  bool busy = true;
  String? error, filter, category;
  String sort = 'balance';
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

  Widget accountCard(Json p) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => details(p),
          borderRadius: BorderRadius.circular(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: canvas,
                child: Icon(
                  supplier
                      ? Icons.local_shipping_outlined
                      : Icons.person_outline,
                  color: navy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p['name']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if ('${p['nickname'] ?? ''}'.isNotEmpty)
                      Text(
                        '${p['nickname']}',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    Text(
                      balanceLabel(p),
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              compactAmount(((p['balance'] as num?) ?? 0).abs()),
            ],
          ),
        ),
        if ('${p['phone'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '${p['phone']}',
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.right,
            ),
          ),
        if ('${p['alternatePhone'] ?? ''}'.isNotEmpty)
          Text(
            '${p['alternateContact'] ?? 'هاتف إضافي'}: ${p['alternatePhone']}',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        if (supplier && '${p['category'] ?? ''}'.isNotEmpty)
          Text(
            '${p['category']}',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        if ('${p[supplier ? 'deliveryDays' : 'paymentSchedule'] ?? ''}'
            .isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${supplier ? 'التوريد' : 'اتفاق الدفع'}: ${p[supplier ? 'deliveryDays' : 'paymentSchedule']}',
              style: const TextStyle(color: navy, fontSize: 12),
            ),
          ),
        if ('${p['lastNote'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${p['lastNote']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ),
        if (!widget.picker) ...[
          const Divider(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => transact(supplier ? 'Purchase' : 'Debt', p),
                icon: const Icon(Icons.add, size: 18),
                label: Text(supplier ? 'فاتورة' : 'دين'),
              ),
              TextButton.icon(
                onPressed: () => transact('Payment', p),
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('دفعة'),
              ),
              if (!supplier)
                TextButton(
                  onPressed: () => details(p),
                  child: const Text('كشف الحساب'),
                ),
            ],
          ),
        ],
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: load,
      child: Width(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: [
            Heading(
              title,
              action: IconButton.filled(
                tooltip: 'إضافة',
                onPressed: add,
                icon: const Icon(Icons.add),
              ),
            ),
            Text(
              products
                  ? 'أسعار الأصناف ووحداتها في مكان واحد.'
                  : supplier
                  ? 'ذمم الموردين وفواتير البضائع'
                  : 'حسابات الزبائن والديون',
              style: const TextStyle(color: muted),
            ),
            if (supplier)
              const Text(
                'أضف المورد، ثم سجّل مشترياته ومدفوعاته.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            const SizedBox(height: 18),
            if (!products && overview != null)
              Surface(
                child: Row(
                  children: [
                    Expanded(
                      child: metric(
                        supplier
                            ? 'إجمالي المستحق للموردين'
                            : 'إجمالي المستحق على الزبائن',
                        overview!['outstanding'],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      children: [
                        Text(
                          '${overview!['total']}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          supplier ? 'مورد' : 'زبون',
                          style: const TextStyle(color: muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (!products && !widget.picker) ...[
              Row(
                children: [
                  Expanded(
                    child: BusyButton(
                      label: supplier ? 'فاتورة مشتريات' : 'تسجيل دين',
                      background: orange,
                      onPressed: () => transact(supplier ? 'Purchase' : 'Debt'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: BusyButton(
                      label: 'تسجيل دفعة',
                      onPressed: () => transact('Payment'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: search,
              decoration: InputDecoration(
                hintText: 'بحث في $title',
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (_) {
                debounce?.cancel();
                debounce = Timer(
                  const Duration(milliseconds: 350),
                  () => load(),
                );
              },
            ),
            const SizedBox(height: 12),
            if (!products) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final e in <String?, String>{
                      null: 'الكل',
                      supplier ? 'owing' : 'debt': 'مستحقات',
                      'credit': 'رصيد دائن',
                      'scheduled': supplier ? 'توريد مجدول' : 'اتفاق دفع',
                      'settled': 'مسدّد',
                    }.entries)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: ChoiceChip(
                          label: Text(
                            '${e.value}${overview == null ? '' : ' (${overview![e.key == null
                                          ? 'total'
                                          : e.key == 'debt'
                                          ? 'owing'
                                          : e.key] ?? 0})'}',
                          ),
                          selected: filter == e.key,
                          onSelected: (_) {
                            setState(() => filter = e.key);
                            load();
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: sort,
                decoration: const InputDecoration(labelText: 'ترتيب حسب'),
                isExpanded: true,
                items:
                    {
                          'balance': 'الأعلى رصيداً',
                          if (modern) 'balanceAsc': 'الأقل رصيداً',
                          if (modern) 'recent': 'آخر حركة',
                          'name': 'الاسم',
                        }.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                onChanged: (v) {
                  sort = v!;
                  load();
                },
              ),
            ],
            if ((supplier || products) &&
                (overview?['categories'] as List? ?? []).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: ChoiceChip(
                          label: const Text('كل الأنواع'),
                          selected: category == null,
                          onSelected: (_) {
                            category = null;
                            load();
                          },
                        ),
                      ),
                      for (final c in overview!['categories'])
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: ChoiceChip(
                            label: Text('$c'),
                            selected: category == c,
                            onSelected: (_) {
                              category = c;
                              load();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
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
            ...rows.map(
              (p) => products
                  ? Card(
                      elevation: 0,
                      child: ListTile(
                        title: Text('${p['name']}'),
                        subtitle: Text('${p['unit']} · ${p['category']}'),
                        trailing: compactAmount(p['salePrice']),
                        onTap: () => details(p),
                      ),
                    )
                  : accountCard(p),
            ),
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
            const SizedBox(height: 30),
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

class PartyForm extends StatefulWidget {
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        '${widget.existing == null ? 'إضافة' : 'تعديل'} ${widget.supplier ? 'مورد' : 'زبون'}',
      ),
    ),
    body: Width(
      child: ListView(
        padding: const EdgeInsets.all(20),
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
                field(
                  fields['phone']!,
                  'رقم الجوال (اختياري)',
                  max: 30,
                  keyboard: TextInputType.phone,
                ),
                if (widget.supplier)
                  field(fields['category']!, 'نوع التوريد (اختياري)', max: 50)
                else
                  field(fields['nickname']!, 'اللقب (اختياري)', max: 80),
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

  Future<Json> load() =>
      Scope.of(context).api.get('/api/parties/${widget.id}');

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

class ProductForm extends StatefulWidget {
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.existing == null ? 'إضافة صنف' : 'تعديل الصنف'),
    ),
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
                Wrap(
                  spacing: 6,
                  children: [
                    for (final unit in ['قطعة', 'كغم', 'ربطة', 'كرتونة', 'لتر'])
                      ActionChip(
                        label: Text(unit),
                        onPressed: () => fields['unit']!.text = unit,
                      ),
                  ],
                ),
                field(fields['unit']!, 'الوحدة', required: true, max: 30),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final category in [
                      'عام',
                      'مواد تموينية',
                      'خضار وفواكه',
                      'مخبوزات',
                      'منظفات',
                    ])
                      ActionChip(
                        label: Text(category),
                        onPressed: () => fields['category']!.text = category,
                      ),
                  ],
                ),
                field(fields['category']!, 'التصنيف', required: true, max: 60),
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'تعديل الأسعار يخص الفواتير الجديدة. الفواتير المحفوظة تحتفظ بأسعارها.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
                for (final e in {
                  'salePrice': 'سعر البيع',
                  'purchasePrice': 'سعر الشراء',
                }.entries)
                  field(
                    fields[e.key]!,
                    '${e.value} — شيكل',
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) =>
                        cents(v ?? '') == null ? 'أدخل سعراً صحيحاً' : null,
                  ),
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
