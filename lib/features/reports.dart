import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../services/receipts.dart';
import '../services/export.dart';
import '../ui/theme.dart';
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
      next = DateTimeRange(start: DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 6)), end: now);
    } else if (value == 'الشهر الماضي') {
      final first = DateTime(now.year, now.month - 1, 1);
      next = DateTimeRange(start: first,
          end: DateTime(now.year, now.month, 0));
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
    child: Text('$label: $value', style: const TextStyle(color: muted, fontSize: 12)),
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
            onPressed: session.isOffline || session.pendingSync > 0 ? null : () async {
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
            const Text('اختَر الفترة التي تريد مراجعتها. الذمم بالأسفل هي الأرصدة الحالية، وليست فقط حركات الفترة.',
                style: TextStyle(color: muted)),
            const SizedBox(height: 12),
            Wrap(spacing: 6, children: [
              for (final label in ['هذا الشهر', 'آخر 7 أيام', 'الشهر الماضي'])
                ChoiceChip(
                  label: Text(label),
                  selected: selection == label,
                  onSelected: (_) => selectPeriod(label),
                ),
            ]),
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
                  setState(() { range = next; selection = 'فترة مخصصة'; future = load(); });
                }
              },
              icon: const Icon(Icons.date_range),
              label: Text('${day(range.start)} — ${day(range.end)}'),
            ),
            if (session.pendingSync > 0 || session.isOffline)
              Surface(
                color: const Color(0xFFFFF1DF),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('تنبيه بخصوص الأرقام', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(session.isOffline
                      ? 'هذه أرقام آخر نسخة تم تنزيلها من الخادم، وقد لا تطابق الوضع الحالي.'
                      : 'هناك ${session.pendingSync} حركة على الجهاز لم تُسجّل على الخادم بعد.'),
                    const Text('الطباعة متوقفة مؤقتاً إلى أن تتأكد مزامنة البيانات، حتى لا تخرج نسخة محاسبية غير مكتملة.'),
                  ],
                ),
              ),
            FutureBuilder<Json>(
              future: future,
              builder: (context, s) {
                if (s.hasError) {
                  return Empty('التقرير غير متاح', '${s.error}',
                    action: OutlinedButton(
                      onPressed: () => setState(() => future = load()),
                      child: const Text('إعادة المحاولة'),
                    ),
                  );
                }
                if (!s.hasData) {
                  return const Center(child: Padding(
                    padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
                }
                final summary = Map<String, dynamic>.from(s.data!['summary'] as Map);
                final cash = Map<String, dynamic>.from(s.data!['cash'] as Map);
                return Column(children: [
                  Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Heading('1. المقبوضات والمدفوعات'),
                      Row(children: [
                        Expanded(child: metric('قبضنا من الزبائن', summary['received'])),
                        const SizedBox(width: 8),
                        Expanded(child: metric('دفعنا للموردين', summary['paid'], color: orange)),
                      ]),
                      explanation('ماذا يشمل؟', 'دفعات الزبائن والموردين خلال الفترة، نقداً وبالتحويلات المؤكدة.'),
                    ],
                  )),
                  Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Heading('2. حركة النقد في الصندوق'),
                      Row(children: [
                        Expanded(child: metric('نقد دخل', cash['customerCashIn'])),
                        const SizedBox(width: 8),
                        Expanded(child: metric('نقد خرج', cash['supplierCashOut'], color: orange)),
                      ]),
                      const Divider(height: 26),
                      metric('صافي حركة النقد', cash['netCash']),
                      explanation('مهم', 'هذا الفرق بين النقد الداخل والخارج خلال الفترة؛ ليس ربح المحل ولا الرصيد البنكي.'),
                    ],
                  )),
                  Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Heading('3. الديون الحالية'),
                      Row(children: [
                        Expanded(child: metric('الزبائن مدينون لنا', summary['receivables'])),
                        const SizedBox(width: 8),
                        Expanded(child: metric('نحن مدينون للموردين', summary['payables'], color: orange)),
                      ]),
                      explanation('انتبه', 'هذه الأرصدة حتى الآن، مهما كانت الفترة المحددة فوق.'),
                    ],
                  )),
                  const Surface(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Heading('شو التقرير ما بيحسب؟'),
                      Text('هذا تقرير ذمم وحركة قبض ودفع؛ لا يحسب أرباح المبيعات أو تكلفة البضاعة أو المصاريف التشغيلية.'),
                    ],
                  )),
                ]);
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
  String? kind, error, partyKind;
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
      final data = await api.get(
        '/api/transactions',
        query: {...query, 'page': page + 1, 'size': 30},
      );
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

  Future<void> printAll() async {
    final params = query;
    final selectedRange = range;
    final selectedKind = kind;
    final selectedLabel = [
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
        final response = await session.api.get(
          '/api/transactions',
          query: {...params, 'page': p++, 'size': 100},
        );
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
      await Exports.history(
        session.shopName,
        entries,
        printNames,
        selectedRange,
        selectedKind,
        selectionLabel: selectedLabel,
      );
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'سجل المشتريات والمدفوعات',
        maxLines: 2,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
      actions: [
        IconButton(
          tooltip: 'طباعة السجل كاملاً',
          onPressed: printing || busy ? null : printAll,
          icon: printing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.print_outlined),
        ),
      ],
    ),
    body: Width(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (Scope.of(context).ledgerV2) ...[
            Wrap(
              spacing: 6,
              children: [
                for (final v in {
                  'all': 'الكل',
                  'Customer': 'الزبائن',
                  'Supplier': 'الموردون',
                  'payments': 'المدفوعات',
                }.entries)
                  ChoiceChip(
                    label: Text(v.value),
                    selected: v.key == 'payments'
                        ? kind == 'Payment' && partyKind == null
                        : v.key == 'all'
                        ? kind == null && partyKind == null
                        : partyKind == v.key,
                    onSelected: printing
                        ? null
                        : (_) {
                            partyKind = ['Customer', 'Supplier'].contains(v.key)
                                ? v.key
                                : null;
                            kind = v.key == 'payments' ? 'Payment' : null;
                            load();
                          },
                  ),
              ],
            ),
            if (overview != null)
              Surface(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: metric(
                            'الفواتير بعد الخصم',
                            overview!['invoices'],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: metric(
                            'المقبوضات المؤكدة',
                            overview!['received'],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: metric('المدفوع للموردين', overview!['paid']),
                        ),
                        Expanded(
                          child: Text(
                            'حوالات معلّقة: ${overview!['pendingCount']}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            FilterChip(
              label: const Text('الحوالات بانتظار التأكيد فقط'),
              selected: pendingOnly,
              onSelected: printing
                  ? null
                  : (v) {
                      pendingOnly = v;
                      load();
                    },
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 6,
            children: [
              for (final e in <String?, String>{null: 'الكل', ...kinds}.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: kind == e.key,
                  onSelected: printing
                      ? null
                      : (_) {
                          kind = e.key;
                          load();
                        },
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  range == null
                      ? 'كل الفترات'
                      : '${day(range!.start)} — ${day(range!.end)}',
                ),
              ),
              IconButton(
                tooltip: 'اختيار الفترة',
                onPressed: printing
                    ? null
                    : () async {
                        final r = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                          initialDateRange: range,
                        );
                        if (r != null) {
                          range = r;
                          load();
                        }
                      },
                icon: const Icon(Icons.date_range),
              ),
              if (range != null)
                IconButton(
                  tooltip: 'إلغاء الفترة',
                  onPressed: printing
                      ? null
                      : () {
                          range = null;
                          load();
                        },
                  icon: const Icon(Icons.clear),
                ),
            ],
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
            const Empty('لا توجد حركات', 'لا توجد حركات ضمن الفترة المختارة.'),
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
