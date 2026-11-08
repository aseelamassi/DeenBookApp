import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:uuid/uuid.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/ledger.dart';
import '../services/receipts.dart';
import 'invoice_items.dart';
import '../core/session.dart';
import '../core/storage.dart';
import '../ui/theme.dart';
import '../ui/design.dart';
import '../ui/widgets.dart';
import 'catalog.dart';
import 'reports.dart';

Future<void> quickAction(BuildContext context) async {
  final result = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Heading(
              '⚡ إجراء سريع في دفتر دين',
              action: IconButton(
                tooltip: 'إغلاق',
                onPressed: () => Navigator.pop(c),
                icon: const Icon(Icons.close),
              ),
            ),
            for (final row in [
              [('Debt', 'تسجيل دين زبون'), ('Payment', 'قبض دفعة زبون')],
              [
                ('Purchase', 'تسجيل فاتورة مورد'),
                ('SupplierPayment', 'سداد دفعة لمورد'),
              ],
              [('Customer', 'زبون جديد'), ('Product', 'صنف جديد')],
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    for (var i = 0; i < row.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: DesignButton(
                          row[i].$2,
                          icon: row[i].$1.contains('Payment')
                              ? Icons.check
                              : Icons.add,
                          background:
                              row[i].$1 == 'Debt' || row[i].$1 == 'Purchase'
                              ? paleOrange
                              : lavender,
                          foreground:
                              row[i].$1 == 'Debt' || row[i].$1 == 'Purchase'
                              ? orange
                              : navy,
                          onTap: () => Navigator.pop(c, row[i].$1),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
  if (result != null && context.mounted) {
    await open(
      context,
      result == 'Customer'
          ? const PartyForm(supplier: false)
          : result == 'Product'
          ? const ProductForm()
          : TransactionScreen(
              kind: result == 'SupplierPayment' ? 'Payment' : result,
              supplier: result == 'SupplierPayment' || result == 'Purchase',
            ),
    );
  }
}

class TransactionScreen extends StatefulWidget {
  const TransactionScreen({
    super.key,
    this.kind = 'Debt',
    this.party,
    this.initialProduct,
    this.voice = false,
    this.supplier = false,
  });
  final String kind;
  final Json? party, initialProduct;
  final bool voice, supplier;
  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> {
  final form = GlobalKey<FormState>();
  final total = TextEditingController(),
      paid = TextEditingController(text: '0'),
      note = TextEditingController(),
      reference = TextEditingController(),
      invoice = TextEditingController(),
      discount = TextEditingController(text: '0'),
      counterparty = TextEditingController(),
      handed = TextEditingController();
  final lines = <InvoiceLine>[];
  bool itemMode = false, waiting = false, keepChange = false, receipt = false;
  bool get modern => Scope.of(context).ledgerV2;
  int get gross => cents(total.text) ?? 0;
  int get net => gross - (cents(discount.text) ?? 0);
  int get requestedPayment => isInvoice ? (cents(paid.text) ?? 0) : gross;
  int get actualPayment => modern && !supplier && method == 'Cash' && hasPayment
      ? effectivePayment(requestedPayment, cents(handed.text) ?? 0, keepChange)
      : requestedPayment;
  bool get pendingTransfer =>
      modern && kind == 'Payment' && !supplier && method != 'Cash' && waiting;
  void recalculate() {
    if (mounted) setState(() {});
  }

  void itemsChanged() => setState(() {
    total.text = decimalMoney(lines.fold(0, (sum, p) => sum + p.total));
  });
  final speech = SpeechToText();
  Json? party, pending;
  late String kind;
  String method = 'Cash';
  bool supplier = false,
      busy = false,
      restoring = true,
      listening = false,
      hadUncertain = false;
  String? error;
  DateTime when = DateTime.now();
  late PendingOperation draft;
  bool get isInvoice => kind == 'Debt' || kind == 'Purchase';
  bool get hasPayment =>
      kind == 'Payment' || (isInvoice && (cents(paid.text) ?? 0) > 0);
  @override
  void initState() {
    super.initState();
    party = widget.party;
    kind = widget.kind;
    supplier =
        widget.supplier || kind == 'Purchase' || party?['kind'] == 'Supplier';
    counterparty.text = party?['name'] ?? '';
    for (final c in [total, paid, discount, handed]) {
      c.addListener(recalculate);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => restore());
  }

  Future<void> restore() async {
    final s = Scope.of(context);
    draft = PendingOperation(s.api.storage, s.shopId);
    try {
      final data = await draft.read();
      if (data != null) {
        pending = data;
        hadUncertain = true;
        kind = data['kind'];
        total.text = '${data['amount']}';
        paid.text = '${data['paidNow']}';
        note.text = data['note'] ?? '';
        reference.text = data['reference'] ?? '';
        invoice.text = data['invoiceNumber'] ?? '';
        discount.text = '${data['discount'] ?? 0}';
        counterparty.text = data['counterpartyName'] ?? '';
        waiting = data['pendingConfirmation'] == true;
        lines.addAll(
          (data['items'] as List? ?? []).map(
            (p) => InvoiceLine.fromJson(Map<String, dynamic>.from(p)),
          ),
        );
        itemMode = lines.isNotEmpty;
        method = data['method'];
        when = DateTime.parse(data['occurredAt']).toLocal();
        party = await s.api.get('/api/parties/${data['partyId']}');
        supplier = party?['kind'] == 'Supplier';
      }
    } catch (e) {
      error = '$e';
    } finally {
      if (pending == null &&
          widget.initialProduct != null &&
          mounted &&
          modern) {
        itemMode = true;
        lines.add(InvoiceLine.product(widget.initialProduct!, supplier));
        itemsChanged();
      }
      if (mounted) setState(() => restoring = false);
    }
  }

  @override
  void dispose() {
    speech.cancel();
    for (final c in [
      total,
      paid,
      note,
      reference,
      invoice,
      discount,
      counterparty,
      handed,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> choose() async {
    final p = await open<Json>(
      context,
      CatalogScreen(mode: supplier ? 'suppliers' : 'customers', picker: true),
    );
    if (p != null && mounted) {
      setState(() {
        party = p;
        counterparty.text = p['name'];
      });
    }
  }

  Future<void> dictate() async {
    if (listening) {
      await speech.stop();
      if (mounted) setState(() => listening = false);
      return;
    }
    try {
      final available = await speech.initialize(
        onStatus: (s) {
          if (mounted) setState(() => listening = s == 'listening');
        },
        onError: (_) {
          if (mounted) {
            setState(() => listening = false);
            message(context, 'تعذّر التعرف على الصوت. يمكنك كتابة الوصف.');
          }
        },
      );
      if (!available) {
        if (mounted) {
          message(
            context,
            'اسمح بالوصول إلى الميكروفون والتعرف على الكلام من إعدادات الجهاز.',
          );
        }
        return;
      }
      final locales = await speech.locales();
      final arabic = locales
          .where((l) => l.localeId.startsWith('ar'))
          .firstOrNull;
      await speech.listen(
        onResult: (r) {
          if (mounted) setState(() => note.text = r.recognizedWords);
        },
        listenOptions: SpeechListenOptions(
          localeId: arabic?.localeId,
          listenMode: ListenMode.dictation,
          partialResults: true,
        ),
      );
    } catch (_) {
      if (mounted) message(context, 'الإدخال الصوتي غير متاح على هذا الجهاز.');
    }
  }

  Future<void> save() async {
    if (pending != null &&
        !modern &&
        [
          'discount',
          'items',
          'counterpartyName',
          'pendingConfirmation',
        ].any(pending!.containsKey)) {
      setState(
        () => error =
            'يحتاج الخادم إلى التحديث لحفظ هذه المسودة بأمان. المسودة ما زالت محفوظة.',
      );
      return;
    }
    if (pending == null) {
      if (!form.currentState!.validate()) return;
      if (party == null) {
        message(context, 'اختر ${supplier ? 'المورد' : 'الزبون'} أولاً.');
        return;
      }
    }
    final session = Scope.of(context);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      pending ??= {
        'operationId': const Uuid().v4(),
        'partyId': party!['id'],
        'kind': kind,
        'amount': (kind == 'Payment' ? actualPayment : gross) / 100,
        'paidNow': isInvoice ? actualPayment / 100 : 0,
        if (modern) ...{
          'discount': isInvoice ? (cents(discount.text) ?? 0) / 100 : 0,
          'counterpartyName': counterparty.text.trim(),
          'pendingConfirmation': pendingTransfer,
          'items': isInvoice && itemMode
              ? lines.map((p) => p.toJson()).toList()
              : [],
        },
        'method': hasPayment ? method : 'Cash',
        'occurredAt': when.toUtc().toIso8601String(),
        'reference': hasPayment ? reference.text.trim() : '',
        'invoiceNumber': invoice.text.trim().isEmpty
            ? null
            : invoice.text.trim(),
        'note': note.text.trim(),
      };
      // Persist the exact request before network I/O; retries never create another ID.
      await draft.save(pending!);
      final saved = await session.api.request(
        'POST',
        '/api/transactions',
        body: pending,
      );
      final queued = saved is Map && saved['queued'] == true;
      await draft.clear();
      await session.updatePending();
      if (!queued &&
          receipt &&
          !supplier &&
          kind == 'Payment' &&
          mounted &&
          saved is Map) {
        try {
          await Receipts.payment(
            context,
            party!,
            Map<String, dynamic>.from(saved),
            session.shopName,
          );
        } catch (_) {
          if (mounted) {
            message(
              context,
              'حُفظت الدفعة، وتعذّر فتح المشاركة. يمكنك مشاركتها من كشف الحساب.',
            );
          }
        }
      }
      if (mounted) {
        message(
          context,
          queued
              ? 'تم حفظ الحركة على الجهاز. ستُرسل عند عودة الإنترنت، ولا يظهر أثرها في رصيد الخادم بعد.'
              : 'تمت مزامنة الحركة وحفظها على الخادم',
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (e is ApiFailure && e.uncertain) hadUncertain = true;
      if (e is ApiFailure && !e.uncertain && !hadUncertain) {
        await draft.clear();
        pending = null;
      }
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> discard() async {
    if (!await confirm(
      context,
      'إلغاء المسودة المحفوظة',
      supplier
          ? 'قد تكون الحركة وصلت إلى الخادم. راجع سجل الحركات أولاً. هل تأكدت وتريد حذف المسودة فقط؟'
          : 'قد تكون الحركة وصلت إلى الخادم. راجع كشف الحساب أولاً. هل تأكدت وتريد حذف المسودة فقط؟',
    )) {
      return;
    }
    await draft.clear();
    if (mounted) {
      setState(() {
        pending = null;
        hadUncertain = false;
        error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kind == 'Payment'
                ? (supplier ? 'سداد دفعة لمورد' : 'قبض دفعة / سداد')
                : kind == 'Return'
                ? 'مرتجع'
                : supplier
                ? 'تسجيل فاتورة مورد'
                : 'تسجيل مشتريات (دين)',
            style: appText(16, weight: FontWeight.w900),
          ),
          Text(
            '${party?['name'] ?? 'دفتر دين'} · حفظ ومزامنة البيانات',
            style: appText(10, color: muted),
          ),
        ],
      ),
    ),
    bottomNavigationBar: Material(
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            14,
            10,
            14,
            10 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: BusyButton(
            label: pending != null
                ? 'إعادة محاولة حفظ نفس الحركة'
                : kind == 'Payment'
                ? 'تأكيد وحفظ الدفعة في دفتر دين ✓'
                : kind == 'Return'
                ? 'تأكيد وحفظ المرتجع ✓'
                : 'تأكيد وحفظ المشتريات في دفتر دين ✓',
            background: kind == 'Payment' ? navy : orange,
            busy: busy,
            onPressed: restoring ? null : save,
          ),
        ),
      ),
    ),
    body: restoring
        ? const Center(child: CircularProgressIndicator())
        : Width(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (pending != null)
                  Surface(
                    color: paleOrange,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'لديك حركة بانتظار التأكد من حفظها',
                          style: appText(14, weight: FontWeight.w800),
                        ),
                        const Text(
                          'إعادة المحاولة تستخدم نفس الحركة المحفوظة لمنع تكرارها.',
                        ),
                        Wrap(
                          children: [
                            TextButton(
                              onPressed: () => open(
                                context,
                                supplier
                                    ? const HistoryScreen()
                                    : PartyDetail(id: pending!['partyId']),
                              ),
                              child: Text(
                                supplier ? 'عرض سجل الحركات' : 'عرض كشف الحساب',
                              ),
                            ),
                            TextButton(
                              onPressed: busy ? null : discard,
                              child: const Text('حذف المسودة بعد التحقق'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.party == null && !isInvoice && pending == null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Segments<bool>(
                            items: const {false: 'زبون', true: 'مورد'},
                            selected: supplier,
                            onSelected: (v) => setState(() {
                              supplier = v;
                              party = null;
                            }),
                          ),
                        ),
                      Surface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    supplier ? 'المورد:' : 'الزبون:',
                                    style: appText(12, weight: FontWeight.w800),
                                  ),
                                ),
                                if (party != null)
                                  SoftTag(
                                    '${balanceLabel(party!)}: ${displayMoney((party!['balance'] as num).abs())}',
                                    color: orange,
                                    background: paleOrange,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (widget.party == null && pending == null)
                              Autocomplete<Json>(
                                key: ValueKey('party-search-$supplier'),
                                displayStringForOption: (p) => '${p['name']}',
                                optionsBuilder: (query) async {
                                  final text = query.text.trim();
                                  // Fetch suggestions as the user types; never navigate away.
                                  try {
                                    final response = await Scope.of(context).api.get(
                                      supplier ? '/api/suppliers' : '/api/customers',
                                      query: {'search': text, 'sort': 'name', 'size': 30},
                                    );
                                    return (response['items'] as List)
                                        .map((p) => Map<String, dynamic>.from(p));
                                  } catch (_) {
                                    return <Json>[];
                                  }
                                },
                                onSelected: (chosen) async {
                                  final details = await Scope.of(context).api.get('/api/parties/${chosen['id']}');
                                  if (mounted) setState(() {
                                    party = Map<String, dynamic>.from(details);
                                    counterparty.text = '${party!['name']}';
                                  });
                                },
                                fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
                                    TextFormField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  decoration: InputDecoration(
                                    hintText: 'ابحث باسم ${supplier ? 'المورد' : 'الزبون'} واختر من الاقتراحات',
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: const Icon(Icons.arrow_drop_down),
                                  ),
                                  onChanged: (value) {
                                    if (party != null && value.trim() != '${party!['name']}') {
                                      setState(() => party = null);
                                    }
                                  },
                                ),
                              )
                            else
                              ListTile(
                                tileColor: const Color(0xFFF7F8FB),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                leading: const Icon(Icons.person_outline),
                                title: Text('${party?['name'] ?? 'اختر الزبون'}'),
                                trailing: const Icon(Icons.lock_outline),
                              ),
                          ],
                        ),
                      ),
                      IgnorePointer(
                        ignoring: pending != null || busy,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (modern && isInvoice) ...[
                              Segments<bool>(
                                items: const {
                                  false: 'المسار السريع (مبلغ مباشر)',
                                  true: 'اختيار أصناف (بالقطعة/الوزن)',
                                },
                                selected: itemMode,
                                onSelected: (v) {
                                  setState(() => itemMode = v);
                                  if (itemMode) itemsChanged();
                                },
                              ),
                              const SizedBox(height: 12),
                              if (itemMode)
                                InvoiceItems(
                                  lines: lines,
                                  purchase: supplier,
                                  onChanged: itemsChanged,
                                ),
                            ],
                            Surface(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'المبلغ الإجمالي بالشيكل (₪):',
                                    style: appText(12, weight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    key: const Key('transaction-amount'),
                                    controller: total,
                                    enabled: !itemMode,
                                    textAlign: TextAlign.center,
                                    style: appText(28, weight: FontWeight.w900),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: InputDecoration(
                                      hintText: '0',
                                      hintStyle: appText(
                                        28,
                                        color: muted,
                                        weight: FontWeight.w900,
                                      ),
                                      fillColor: const Color(0xFFF7F8FB),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 6,
                                          ),
                                    ),
                                    validator: (v) => (cents(v ?? '') ?? 0) <= 0
                                        ? 'أدخل مبلغاً أكبر من صفر وبدقتين عشريتين'
                                        : null,
                                  ),
                                  if (kind == 'Payment') ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        ActionChip(
                                          label: const Text('100 شيكل'),
                                          onPressed: () => total.text = '100',
                                        ),
                                        if (amountCents(party?['balance']) > 0)
                                          ActionChip(
                                            label: const Text('كامل المستحق'),
                                            onPressed: () =>
                                                total.text = decimalMoney(
                                                  amountCents(
                                                    party?['balance'],
                                                  ),
                                                ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (isInvoice)
                              Surface(
                                child: ExpansionTile(
                                  maintainState: true,
                                  tilePadding: EdgeInsets.zero,
                                  title: Text(
                                    'خصم أو دفعة مع المشتريات (اختياري)',
                                    style: appText(12, weight: FontWeight.w800),
                                  ),
                                  children: [
                                    if (modern)
                                      field(
                                        discount,
                                        'الخصم — شيكل',
                                        keyboard:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        validator: (v) {
                                          final n = cents(v ?? '');
                                          return n == null || n >= gross
                                              ? 'الخصم من صفر إلى أقل من قيمة الفاتورة'
                                              : null;
                                        },
                                      ),
                                    field(
                                      paid,
                                      'المبلغ المدفوع من الزبون — شيكل',
                                      keyboard:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      validator: (v) {
                                        final n = cents(v ?? '');
                                        return n == null ||
                                                ((supplier || !modern) &&
                                                    n > net)
                                            ? 'أدخل دفعة صحيحة لا تتجاوز صافي فاتورة المورد'
                                            : null;
                                      },
                                    ),
                                    field(
                                      invoice,
                                      'رقم الفاتورة (اختياري)',
                                      max: 100,
                                    ),
                                  ],
                                ),
                              ),
                            if (hasPayment)
                              Surface(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'وسيلة الدفع',
                                      style: appText(
                                        12,
                                        weight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Column(
                                      children: [
                                        for (var row = 0; row < 2; row++)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            child: Row(
                                              children: [
                                                for (
                                                  var i = row * 2;
                                                  i < row * 2 + 2;
                                                  i++
                                                ) ...[
                                                  if (i % 2 == 1)
                                                    const SizedBox(width: 8),
                                                  Expanded(
                                                    child: DesignButton(
                                                      methods.values.elementAt(
                                                        i,
                                                      ),
                                                      icon: i == 0
                                                          ? Icons
                                                                .payments_outlined
                                                          : i == 3
                                                          ? Icons
                                                                .account_balance_outlined
                                                          : Icons
                                                                .account_balance_wallet_outlined,
                                                      background:
                                                          method ==
                                                              methods.keys
                                                                  .elementAt(i)
                                                          ? navy
                                                          : canvas,
                                                      foreground:
                                                          method ==
                                                              methods.keys
                                                                  .elementAt(i)
                                                          ? Colors.white
                                                          : navy,
                                                      onTap: () => setState(
                                                        () => method = methods
                                                            .keys
                                                            .elementAt(i),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (method != 'Cash') ...[
                                      const SizedBox(height: 12),
                                      field(
                                        reference,
                                        'اسم المحوِّل (بنك / محفظة / جوال باي)',
                                        required: false,
                                        max: 100,
                                      ),
                                    ],
                                    if (modern &&
                                        kind == 'Payment' &&
                                        !supplier &&
                                        method != 'Cash')
                                      CheckboxListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text('الحوالة لم تصل بعد'),
                                        subtitle: const Text(
                                          'تُحفظ بانتظار التأكيد، ولا تغيّر الرصيد أو المقبوضات.',
                                        ),
                                        value: waiting,
                                        onChanged: (v) =>
                                            setState(() => waiting = v!),
                                      ),
                                  ],
                                ),
                              ),
                            if (modern &&
                                hasPayment &&
                                method == 'Cash' &&
                                !supplier)
                              Surface(
                                color: const Color(0xFFECFDF5),
                                child: ExpansionTile(
                                  maintainState: true,
                                  tilePadding: EdgeInsets.zero,
                                  title: Text(
                                    'حاسبة الفكّة السريعة (تسجيل الباقي رصيد)',
                                    style: appText(
                                      12,
                                      weight: FontWeight.w800,
                                      color: const Color(0xFF065F46),
                                    ),
                                  ),
                                  subtitle: Text(
                                    'إذا أعطاك الزبون ورقة 20 أو 50 أو 100 أو 200 ₪',
                                    style: appText(10, color: green),
                                  ),
                                  children: [
                                    field(
                                      handed,
                                      'المبلغ المسلّم نقداً (اختياري)',
                                      keyboard:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      validator: (v) {
                                        if (v == null || v.isEmpty) return null;
                                        final n = cents(v);
                                        return n == null || n < requestedPayment
                                            ? 'المسلّم يجب أن يغطي الدفعة'
                                            : null;
                                      },
                                    ),
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        for (final n in [20, 50, 100, 200])
                                          ActionChip(
                                            label: Text('$n'),
                                            onPressed: () => handed.text = '$n',
                                          ),
                                      ],
                                    ),
                                    Text(
                                      'الباقي: ${displayMoney(((cents(handed.text) ?? 0) - requestedPayment).clamp(0, 99999999900) / 100)}',
                                    ),
                                    CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'احتساب الباقي رصيداً للزبون',
                                      ),
                                      value: keepChange,
                                      onChanged: (v) =>
                                          setState(() => keepChange = v!),
                                    ),
                                  ],
                                ),
                              ),
                            if (modern)
                              Surface(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      kind == 'Payment'
                                          ? 'اسم الدافع / المستلم (اختياري):'
                                          : 'اسم الشخص اللي إجا اشترى أو استلم البضاعة (اختياري):',
                                      style: appText(
                                        12,
                                        weight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (!supplier && isInvoice)
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: [
                                          for (final preset in [
                                            'الزبون نفسه',
                                            'ابنه',
                                            'أخوه',
                                            'أحد أفراد العائلة',
                                          ])
                                            DesignButton(
                                              preset,
                                              height: 30,
                                              background: canvas,
                                              onTap: () => counterparty.text =
                                                  preset == 'الزبون نفسه'
                                                  ? (party?['name'] ?? '')
                                                  : preset,
                                            ),
                                        ],
                                      ),
                                    const SizedBox(height: 12),
                                    field(
                                      counterparty,
                                      kind == 'Payment'
                                          ? 'اسم الدافع / المستلم'
                                          : 'مين اللي إجا اشترى / استلم البضاعة؟',
                                      max: 120,
                                    ),
                                  ],
                                ),
                              ),
                            Surface(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    isInvoice ? 'شو اشترى؟ / ملاحظات الفاتورة (اختياري):' : 'البيان / الملاحظة (اختياري):',
                                    style: appText(12, weight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 10),
                                  field(
                                    note,
                                    'وصف الحركة (اختياري)',
                                    lines: 3,
                                    max: 2000,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'التاريخ: ${day(when)}',
                                          style: appText(
                                            11,
                                            color: secondaryText,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'تغيير التاريخ',
                                        onPressed: () async {
                                          final d = await showDatePicker(
                                            context: context,
                                            firstDate: DateTime(2000),
                                            lastDate: DateTime.now(),
                                            initialDate: when,
                                          );
                                          if (d != null && mounted) {
                                            setState(
                                              () => when = DateTime(
                                                d.year,
                                                d.month,
                                                d.day,
                                                when.hour,
                                                when.minute,
                                              ),
                                            );
                                          }
                                        },
                                        icon: const Icon(
                                          Icons.calendar_today_outlined,
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (pending == null)
                                    OutlinedButton.icon(
                                      onPressed: busy ? null : dictate,
                                      icon: Icon(
                                        listening ? Icons.stop : Icons.mic_none,
                                        size: 20,
                                      ),
                                      label: Text(
                                        listening
                                            ? 'إيقاف التسجيل'
                                            : 'إملاء وصف الحركة',
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (modern && party != null)
                        Surface(
                          color: lavender,
                          child: Builder(
                            builder: (_) {
                              final delta = pendingTransfer
                                  ? 0
                                  : isInvoice
                                  ? net - actualPayment
                                  : -(kind == 'Payment'
                                        ? actualPayment
                                        : gross);
                              final next =
                                  amountCents(party!['balance']) + delta;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pendingTransfer
                                        ? 'الرصيد يبقى كما هو حتى وصول الحوالة'
                                        : 'الرصيد المتوقع بعد الحفظ',
                                  ),
                                  amount(next.abs() / 100),
                                  Text(
                                    balanceLabel({
                                      ...party!,
                                      'balance': next / 100,
                                    }),
                                  ),
                                  if (isInvoice)
                                    Text(
                                      'صافي الفاتورة: ${displayMoney(net / 100)}',
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      if (modern &&
                          !supplier &&
                          kind == 'Payment' &&
                          pending == null)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'فتح مسودة إيصال عبر واتساب بعد الحفظ',
                          ),
                          subtitle: const Text('تراجع الرسالة وترسلها بنفسك.'),
                          value: receipt,
                          onChanged: (v) => setState(() => receipt = v!),
                        ),
                      if (error != null)
                        Text(error!, style: const TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ),
  );
}
