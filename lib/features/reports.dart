import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../services/receipts.dart';
import '../services/export.dart';
import '../ui/theme.dart';
import '../ui/design.dart';
import 'catalog.dart';
import '../core/ledger.dart';
import '../ui/widgets.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DateTimeRange range;
  Future<Json>? future;
  String selection = 'هذا الشهر';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    range = DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future ??= load();
  }

  Future<Json> load() async {
    final api = Scope.of(context).api;
    final q = period(range.start, range.end);
    final r = await Future.wait([
      api.get('/api/reports/summary', query: q),
      api.get('/api/reports/cashflow', query: q),
    ]);
    return {'summary': r[0], 'cash': r[1]};
  }

  void selectPeriod(String value) {
    final now = DateTime.now();
    DateTimeRange next;
    if (value == 'آخر 7 أيام') {
      next = DateTimeRange(
        start: DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6)),
        end: now,
      );
    } else if (value == 'الشهر الماضي') {
      final first = DateTime(now.year, now.month - 1, 1);
      next = DateTimeRange(start: first, end: DateTime(now.year, now.month, 0));
    } else {
      next = DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
    }
    setState(() {
      selection = value;
      range = next;
      future = load();
    });
  }

  Widget explanation(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Text(
      '$label: $value',
      style: const TextStyle(color: muted, fontSize: 12),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final session = Scope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('تقارير المحل'),
        actions: [
          IconButton(
            tooltip: 'طباعة التقرير',
            onPressed: session.isOffline || session.pendingSync > 0
                ? null
                : () async {
                    try {
                      final data = await future;
                      if (data == null || !context.mounted) return;
                      await Exports.report(session.shopName, data, range);
                    } catch (e) {
                      if (context.mounted) message(context, e);
                    }
                  },
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
      body: Width(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Heading('ملخص حركة المحل'),
            const Text(
              'اختَر الفترة التي تريد مراجعتها. الذمم بالأسفل هي الأرصدة الحالية، وليست فقط حركات الفترة.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: [
                for (final label in ['هذا الشهر', 'آخر 7 أيام', 'الشهر الماضي'])
                  ChoiceChip(
                    label: Text(label),
                    selected: selection == label,
                    onSelected: (_) => selectPeriod(label),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final next = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                  initialDateRange: range,
                );
                if (next != null) {
                  setState(() {
                    range = next;
                    selection = 'فترة مخصصة';
                    future = load();
                  });
                }
              },
              icon: const Icon(Icons.date_range),
              label: Text('${day(range.start)} — ${day(range.end)}'),
            ),
            if (session.pendingSync > 0 || session.isOffline)
              Surface(
                color: const Color(0xFFFFF1DF),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'تنبيه بخصوص الأرقام',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      session.isOffline
                          ? 'هذه أرقام آخر نسخة تم تنزيلها من الخادم، وقد لا تطابق الوضع الحالي.'
                          : 'هناك ${session.pendingSync} حركة على الجهاز لم تُسجّل على الخادم بعد.',
                    ),
                    const Text(
                      'الطباعة متوقفة مؤقتاً إلى أن تتأكد مزامنة البيانات، حتى لا تخرج نسخة محاسبية غير مكتملة.',
                    ),
                  ],
                ),
              ),
            FutureBuilder<Json>(
              future: future,
              builder: (context, s) {
                if (s.hasError) {
                  return Empty(
                    'التقرير غير متاح',
                    '${s.error}',
                    action: OutlinedButton(
                      onPressed: () => setState(() => future = load()),
                      child: const Text('إعادة المحاولة'),
                    ),
                  );
                }
                if (!s.hasData) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                final summary = Map<String, dynamic>.from(
                  s.data!['summary'] as Map,
                );
                final cash = Map<String, dynamic>.from(s.data!['cash'] as Map);
                return Column(
                  children: [
                    Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Heading('1. المقبوضات والمدفوعات'),
                          Row(
                            children: [
                              Expanded(
                                child: metric(
                                  'قبضنا من الزبائن',
                                  summary['received'],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: metric(
                                  'دفعنا للموردين',
                                  summary['paid'],
                                  color: orange,
                                ),
                              ),
                            ],
                          ),
                          explanation(
                            'ماذا يشمل؟',
                            'دفعات الزبائن والموردين خلال الفترة، نقداً وبالتحويلات المؤكدة.',
                          ),
                        ],
                      ),
                    ),
                    Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Heading('2. حركة النقد في الصندوق'),
                          Row(
                            children: [
                              Expanded(
                                child: metric(
                                  'نقد دخل',
                                  cash['customerCashIn'],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: metric(
                                  'نقد خرج',
                                  cash['supplierCashOut'],
                                  color: orange,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 26),
                          metric('صافي حركة النقد', cash['netCash']),
                          explanation(
                            'مهم',
                            'هذا الفرق بين النقد الداخل والخارج خلال الفترة؛ ليس ربح المحل ولا الرصيد البنكي.',
                          ),
                        ],
                      ),
                    ),
                    Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Heading('3. الديون الحالية'),
                          Row(
                            children: [
                              Expanded(
                                child: metric(
                                  'الزبائن مدينون لنا',
                                  summary['receivables'],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: metric(
                                  'نحن مدينون للموردين',
                                  summary['payables'],
                                  color: orange,
                                ),
                              ),
                            ],
                          ),
                          explanation(
                            'انتبه',
                            'هذه الأرصدة حتى الآن، مهما كانت الفترة المحددة فوق.',
                          ),
                        ],
                      ),
                    ),
                    const Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Heading('شو التقرير ما بيحسب؟'),
                          Text(
                            'هذا تقرير ذمم وحركة قبض ودفع؛ لا يحسب أرباح المبيعات أو تكلفة البضاعة أو المصاريف التشغيلية.',
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            OutlinedButton.icon(
              onPressed: () => open(context, const HistoryScreen()),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('عرض الحركات بالتفصيل'),
            ),
          ],
        ),
      ),
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Json> rows = [];
  final names = <String, String>{};
  DateTimeRange? range;
  String? kind, error, partyKind = 'Customer';
  Json? selectedParty;
  String periodLabel = 'كل الفترات';
  bool pendingOnly = false;
  Json? overview;
  int page = 0, total = 0, generation = 0;
  bool busy = true, printing = false;
  Json get query => {
    if (range != null) ...period(range!.start, range!.end),
    if (kind != null) 'kind': kind,
    if (partyKind != null) 'partyKind': partyKind,
    if (pendingOnly) 'pending': true,
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load({bool more = false}) async {
    final request = ++generation;
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
      final data = selectedParty == null
          ? await api.get(
              '/api/transactions',
              query: {...query, 'page': page + 1, 'size': 30},
            )
          : await accountHistory(selectedParty!, query);
      final entries = (data['items'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      await Future.wait(
        entries
            .map((e) => e['partyId'] as String)
            .toSet()
            .where((id) => !names.containsKey(id))
            .map((id) async {
              final p = await api.get('/api/parties/$id');
              names[id] = '${p['name']}';
            }),
      );
      if (mounted && generation == request) {
        setState(() {
          rows = [...rows, ...entries];
          page++;
          total = data['total'];
          overview = data['overview'] == null
              ? null
              : Map<String, dynamic>.from(data['overview']);
        });
      }
    } catch (e) {
      if (mounted && generation == request) setState(() => error = '$e');
    } finally {
      if (mounted && generation == request) setState(() => busy = false);
    }
  }

  Future<Json> accountHistory(Json party, Json params) async {
    final data = await Scope.of(context).api.get(
      '/api/parties/${party['id']}/statement',
      query: {
        if (params['from'] != null) 'from': params['from'],
        if (params['to'] != null) 'to': params['to'],
      },
    );
    final entries = (data['entries'] as List)
        .map((e) => Map<String, dynamic>.from(e))
        .where(
          (e) =>
              (params['kind'] == null || e['kind'] == params['kind']) &&
              (params['pending'] != true || e['pendingConfirmation'] == true),
        )
        .toList()
        .reversed
        .toList();
    return {
      'items': entries,
      'total': entries.length,
      'overview': historyTotals(entries, supplier: party['kind'] == 'Supplier'),
    };
  }

  Future<void> printAll({bool csv = false}) async {
    final params = query;
    final exportParty = selectedParty;
    final selectedRange = range;
    final selectedKind = kind;
    final selectedLabel = [
      if (exportParty != null) '${exportParty['name']}',
      if (partyKind == 'Customer') 'حركات الزبائن',
      if (partyKind == 'Supplier') 'حركات الموردين',
      if (pendingOnly) 'الحوالات بانتظار التأكيد فقط',
    ].join(' · ');
    final session = Scope.of(context);
    setState(() => printing = true);
    try {
      final entries = <Json>[];
      var p = 1;
      while (true) {
        final response = exportParty == null
            ? await session.api.get(
                '/api/transactions',
                query: {...params, 'page': p++, 'size': 100},
              )
            : await accountHistory(exportParty, params);
        entries.addAll(
          (response['items'] as List).map((e) => Map<String, dynamic>.from(e)),
        );
        if (entries.length >= (response['total'] as int) ||
            (response['items'] as List).isEmpty) {
          break;
        }
      }
      final printNames = <String, String>{};
      for (final id in entries.map((e) => e['partyId'] as String).toSet()) {
        final party = await session.api.get('/api/parties/$id');
        printNames[id] = '${party['name']}';
      }
      if (!mounted) return;
      if (csv) {
        await Exports.historyCsv(context, entries, printNames);
      } else {
        await Exports.history(
          session.shopName,
          entries,
          printNames,
          selectedRange,
          selectedKind,
          selectionLabel: selectedLabel,
        );
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  Future<void> selectPeriod(String value) async {
    if (printing) return;
    final now = DateTime.now();
    DateTimeRange? next;
    if (value == 'مخصص') {
      next = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: now,
        initialDateRange: range,
      );
      if (next == null || !mounted) return;
    } else if (value == 'هذا الشهر') {
      next = DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
    } else if (value == 'الشهر الماضي') {
      next = DateTimeRange(
        start: DateTime(now.year, now.month - 1, 1),
        end: DateTime(now.year, now.month, 0),
      );
    } else if (value == 'آخر 7 أيام') {
      next = DateTimeRange(
        start: DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6)),
        end: now,
      );
    }
    setState(() {
      range = next;
      periodLabel = value;
    });
    load();
  }

  Future<void> chooseAccount() async {
    final result = await open<Json>(
      context,
      CatalogScreen(
        mode: partyKind == 'Supplier' ? 'suppliers' : 'customers',
        picker: true,
      ),
    );
    if (result != null && mounted) {
      setState(() => selectedParty = result);
      load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = Scope.of(context);
    final canExport =
        !busy &&
        !printing &&
        error == null &&
        !session.isOffline &&
        session.pendingSync == 0;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'رجوع',
          onPressed: () => Navigator.maybePop(context),
          icon: const BackButtonIcon(),
        ),
        title: Text(
          'سجل المشتريات والمدفوعات',
          style: appText(14, weight: FontWeight.w900),
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Tooltip(
              message: 'طباعة السجل كاملاً',
              child: DesignButton(
                printing ? 'جاري…' : 'طباعة',
                icon: Icons.print_outlined,
                height: 34,
                background: navy,
                foreground: Colors.white,
                onTap: canExport ? () => printAll() : null,
              ),
            ),
          ),
        ],
      ),
      body: Width(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (session.ledgerV2) ...[
              Segments<String>(
                items: const {
                  'Customer': 'الزبائن',
                  'Supplier': 'الموردون',
                  'payments': 'المدفوعات',
                },
                selected: partyKind ?? (kind == 'Payment' ? 'payments' : 'all'),
                onSelected: (v) {
                  if (printing) return;
                  setState(() {
                    partyKind = v == 'payments' ? null : v;
                    kind = v == 'payments' ? 'Payment' : null;
                    selectedParty = null;
                    pendingOnly = false;
                  });
                  load();
                },
              ),
              const SizedBox(height: 16),
            ],
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'الفترة الزمنية',
                    style: appText(12, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  DesignChips<String>(
                    items: const {
                      'الشهر الماضي': 'الشهر الماضي',
                      'هذا الشهر': 'هذا الشهر',
                      'آخر 7 أيام': 'آخر 7 أيام',
                      'مخصص': 'مخصص',
                      'كل الفترات': 'الكل',
                    },
                    selected: periodLabel,
                    onSelected: selectPeriod,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      for (final start in [true, false]) ...[
                        if (!start) const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: printing ? null : () => selectPeriod('مخصص'),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: canvas,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    start ? 'من تاريخ' : 'إلى تاريخ',
                                    style: appText(10, color: muted),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    range == null
                                        ? 'كل الفترات'
                                        : day(
                                            start ? range!.start : range!.end,
                                          ),
                                    style: appText(11, weight: FontWeight.w800),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'الحساب',
                              style: appText(10, color: secondaryText),
                            ),
                            const SizedBox(height: 6),
                            DesignButton(
                              selectedParty?['name'] ??
                                  (partyKind == 'Supplier'
                                      ? 'كل الموردين ⌄'
                                      : partyKind == 'Customer'
                                      ? 'كل الزبائن ⌄'
                                      : 'اختر زبوناً ⌄'),
                              height: 46,
                              background: canvas,
                              onTap: printing ? null : chooseAccount,
                            ),
                            if (selectedParty != null)
                              TextButton(
                                onPressed: () {
                                  setState(() => selectedParty = null);
                                  load();
                                },
                                child: const Text('إلغاء اختيار الحساب'),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'نوع الحركة',
                              style: appText(10, color: secondaryText),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              key: ValueKey(kind),
                              initialValue: kind ?? 'all',
                              isExpanded: true,
                              style: appText(11, weight: FontWeight.w800),
                              decoration: const InputDecoration(
                                fillColor: canvas,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              items: [
                                for (final e in {
                                  'all': 'كل الحركات',
                                  ...kinds,
                                }.entries)
                                  DropdownMenuItem(
                                    value: e.key,
                                    child: Text(
                                      e.value,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: printing
                                  ? null
                                  : (v) {
                                      setState(
                                        () => kind = v == 'all' ? null : v,
                                      );
                                      load();
                                    },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (session.ledgerV2)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      title: Text(
                        'الحوالات بانتظار التأكيد فقط',
                        style: appText(11),
                      ),
                      value: pendingOnly,
                      onChanged: printing
                          ? null
                          : (v) {
                              setState(() => pendingOnly = v!);
                              load();
                            },
                    ),
                ],
              ),
            ),
            if (overview != null && !busy && error == null) ...[
              Row(
                children: [
                  for (final stat in [
                    ('الفواتير', 'invoices', navy),
                    ('المقبوضات المؤكدة', 'received', green),
                    ('مدفوع للموردين', 'paid', orange),
                  ]) ...[
                    if (stat.$2 != 'invoices') const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            Text(
                              stat.$1,
                              textAlign: TextAlign.center,
                              style: appText(10, color: secondaryText),
                            ),
                            const SizedBox(height: 8),
                            FittedBox(
                              child: amount(
                                overview![stat.$2],
                                size: 19,
                                color: stat.$3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'حوالات بانتظار التأكيد: ${overview!['pendingCount'] ?? 0} · لا تُحتسب ضمن المقبوضات',
                style: appText(10, color: secondaryText),
              ),
              const SizedBox(height: 14),
            ],
            if (session.isOffline || session.pendingSync > 0)
              const Surface(
                color: paleOrange,
                child: Text(
                  'أكمل المزامنة قبل مشاركة التقرير أو طباعته لضمان اكتمال الحركات.',
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: DesignButton(
                    'تصدير Excel / CSV',
                    icon: Icons.file_download_outlined,
                    onTap: canExport ? () => printAll(csv: true) : null,
                    background: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DesignButton(
                    'مشاركة الملخص',
                    icon: Icons.share_outlined,
                    background: const Color(0xFFECFDF5),
                    foreground: green,
                    onTap: canExport && overview != null
                        ? () async {
                            try {
                              await Receipts.draft(
                                context,
                                '${session.shopName}\nسجل المشتريات والمدفوعات\n${Exports.rangeLabel(range)}\n${selectedParty?['name'] ?? (partyKind == 'Supplier'
                                        ? 'الموردون'
                                        : partyKind == 'Customer'
                                        ? 'الزبائن'
                                        : 'كل الحسابات')}\n${kind == null ? 'كل الحركات' : kinds[kind]}\nالفواتير: ${money(overview!['invoices'])}\nالمقبوضات المؤكدة: ${money(overview!['received'])}\nالمدفوع للموردين: ${money(overview!['paid'])}\nحوالات معلّقة غير محتسبة: ${overview!['pendingCount'] ?? 0}',
                                '',
                              );
                            } catch (e) {
                              if (context.mounted) message(context, e);
                            }
                          }
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Heading(
              'الحركات ($total)',
              action: PopupMenuButton<String>(
                tooltip: 'خيارات التقرير',
                onSelected: (v) {
                  if (v == 'report') {
                    open(context, const ReportsScreen());
                  } else {
                    setState(() {
                      partyKind = null;
                      kind = null;
                      selectedParty = null;
                      pendingOnly = false;
                    });
                    load();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'all', child: Text('كل حسابات المحل')),
                  PopupMenuItem(
                    value: 'report',
                    child: Text('تقرير النقد والذمم'),
                  ),
                ],
              ),
            ),
            if (error != null)
              Empty(
                'تعذّر تحميل السجل',
                error!,
                action: OutlinedButton(
                  onPressed: load,
                  child: const Text('إعادة المحاولة'),
                ),
              ),
            if (rows.isEmpty && !busy && error == null)
              const Empty(
                'لا توجد حركات',
                'لا توجد حركات ضمن الفترة المختارة.',
              ),
            ...rows.map(
              (e) => Surface(
                child: entryTile(
                  e,
                  name: names[e['partyId']],
                  onConfirm: () async {
                    if (await Receipts.confirmTransfer(context, e) && mounted) {
                      load();
                    }
                  },
                ),
              ),
            ),
            if (busy) const Center(child: CircularProgressIndicator()),
            if (!busy && rows.length < total)
              OutlinedButton(
                onPressed: () => load(more: true),
                child: const Text('عرض المزيد'),
              ),
          ],
        ),
      ),
    );
  }
}
