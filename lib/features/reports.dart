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

  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: future,
    builder: (context, s) {
      final ready = s.connectionState == ConnectionState.done && s.hasData;
      return Scaffold(
        appBar: AppBar(
          title: const Text('تقارير المحل'),
          actions: [
            IconButton(
              tooltip: 'طباعة التقرير',
              onPressed: ready
                  ? () async {
                      try {
                        await Exports.report(
                          Scope.of(context).shopName,
                          s.data!,
                          range,
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
        body: Width(
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final r = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                    initialDateRange: range,
                  );
                  if (r != null) {
                    setState(() {
                      range = r;
                      future = load();
                    });
                  }
                },
                icon: const Icon(Icons.date_range),
                label: Text('${day(range.start)} — ${day(range.end)}'),
              ),
              const SizedBox(height: 20),
              if (s.hasError)
                Empty(
                  'تعذّر التحميل',
                  '${s.error}',
                  action: OutlinedButton(
                    onPressed: () => setState(() => future = load()),
                    child: const Text('إعادة المحاولة'),
                  ),
                )
              else if (!ready)
                const Center(child: CircularProgressIndicator())
              else ...[
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Heading('حركة الفترة'),
                      Row(
                        children: [
                          Expanded(
                            child: metric(
                              'المقبوضات — كل الوسائل',
                              s.data!['summary']['received'],
                            ),
                          ),
                          Expanded(
                            child: metric(
                              'المدفوعات — كل الوسائل',
                              s.data!['summary']['paid'],
                              color: orange,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Heading('الصندوق النقدي'),
                      metric(
                        'نقد وارد من الزبائن',
                        s.data!['cash']['customerCashIn'],
                      ),
                      const SizedBox(height: 12),
                      metric(
                        'نقد مدفوع للموردين',
                        s.data!['cash']['supplierCashOut'],
                      ),
                      const Divider(height: 30),
                      metric(
                        'صافي النقد خلال الفترة',
                        s.data!['cash']['netCash'],
                      ),
                    ],
                  ),
                ),
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Heading('الذمم الحالية'),
                      const Text(
                        'الأرصدة الآن، بصرف النظر عن الفترة المختارة.',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: metric(
                              'على الزبائن',
                              s.data!['summary']['receivables'],
                            ),
                          ),
                          Expanded(
                            child: metric(
                              'للموردين',
                              s.data!['summary']['payables'],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              OutlinedButton.icon(
                onPressed: () => open(context, const HistoryScreen()),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('سجل المشتريات والمدفوعات'),
              ),
            ],
          ),
        ),
      );
    },
  );
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
