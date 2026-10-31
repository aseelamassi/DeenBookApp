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
import '../ui/widgets.dart';
import 'catalog.dart';
import 'reports.dart';

Future<void> quickAction(BuildContext context) async {
  final result = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Heading('ماذا تريد أن تسجّل؟'),
            ...{
              'Debt': 'دين على زبون',
              'Purchase': 'مشتريات من مورد',
              'Payment': 'دفعة',
              'Return': 'مرتجع',
            }.entries.map(
              (e) => ListTile(
                title: Text(e.value),
                leading: Icon(
                  e.key == 'Payment'
                      ? Icons.payments_outlined
                      : Icons.receipt_long_outlined,
                ),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.pop(c, e.key),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (result != null && context.mounted) {
    await open(context, TransactionScreen(kind: result));
  }
}

class TransactionScreen extends StatefulWidget {
  const TransactionScreen({
    super.key,
    this.kind = 'Debt',
    this.party,
    this.voice = false,
    this.supplier = false,
  });
  final String kind;
  final Json? party;
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
      await draft.clear();
      session.changed();
      if (receipt && !supplier && kind == 'Payment' && mounted && saved is Map) {
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
        message(context, 'تم حفظ الحركة');
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
      title: Text(
        '${kinds[kind]}${kind == 'Payment' ? (supplier ? ' للمورد' : ' من الزبون') : ''}',
      ),
    ),
    body: restoring
        ? const Center(child: CircularProgressIndicator())
        : Width(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (pending != null)
                  Surface(
                    color: const Color(0xFFFFF3E8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'لديك حركة بانتظار التأكد من حفظها',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
                          padding: const EdgeInsets.only(bottom: 16),
                          child: SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: false, label: Text('زبون')),
                              ButtonSegment(value: true, label: Text('مورد')),
                            ],
                            selected: {supplier},
                            onSelectionChanged: (v) => setState(() {
                              supplier = v.first;
                              party = null;
                            }),
                          ),
                        ),
                      Surface(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            party?['name'] ??
                                'اختر ${supplier ? 'المورد' : 'الزبون'}',
                          ),
                          subtitle: Text(
                            widget.party != null
                                ? 'تُسجّل الحركة لهذا الحساب'
                                : party == null
                                ? 'الحساب المرتبط بالحركة'
                                : balanceLabel(party!),
                          ),
                          leading: const Icon(Icons.person_outline),
                          trailing: widget.party == null && pending == null
                              ? const Icon(Icons.chevron_left)
                              : const Icon(Icons.lock_outline, size: 18),
                          onTap: widget.party == null && pending == null
                              ? choose
                              : null,
                        ),
                      ),
                      IgnorePointer(
                        ignoring: pending != null || busy,
                        child: Column(
                          children: [
                            if (modern && isInvoice) ...[
                              SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment(
                                    value: false,
                                    label: Text('مبلغ مباشر'),
                                  ),
                                  ButtonSegment(
                                    value: true,
                                    label: Text('من الأصناف'),
                                  ),
                                ],
                                selected: {itemMode},
                                onSelectionChanged: (v) {
                                  setState(() => itemMode = v.first);
                                  if (itemMode) itemsChanged();
                                },
                              ),
                              const SizedBox(height: 16),
                              if (itemMode)
                                InvoiceItems(
                                  lines: lines,
                                  purchase: supplier,
                                  onChanged: itemsChanged,
                                ),
                            ],
                            field(
                              total,
                              'المبلغ — شيكل',
                              enabled: !itemMode,
                              keyboard: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              validator: (v) => (cents(v ?? '') ?? 0) <= 0
                                  ? 'أدخل مبلغاً أكبر من صفر وبدقتين عشريتين'
                                  : null,
                            ),
                            if (modern)
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  if (isInvoice && !itemMode)
                                    for (final n in [5, 10, 20, 50, 100])
                                      ActionChip(
                                        label: Text('+$n'),
                                        onPressed: () => total.text =
                                            decimalMoney(gross + n * 100),
                                      ),
                                  if (kind == 'Payment') ...[
                                    ActionChip(
                                      label: const Text('100 شيكل'),
                                      onPressed: () => total.text = '100',
                                    ),
                                    if (amountCents(party?['balance']) > 0)
                                      ActionChip(
                                        label: const Text('كامل المستحق'),
                                        onPressed: () =>
                                            total.text = decimalMoney(
                                              amountCents(party?['balance']),
                                            ),
                                      ),
                                  ],
                                ],
                              ),
                            if (modern && isInvoice)
                              field(
                                discount,
                                'الخصم — شيكل',
                                keyboard: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                validator: (v) {
                                  final n = cents(v ?? '');
                                  return n == null || n >= gross
                                      ? 'الخصم من صفر إلى أقل من قيمة الفاتورة'
                                      : null;
                                },
                              ),
                            if (isInvoice)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: TextFormField(
                                  controller: paid,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'المدفوع الآن — شيكل',
                                  ),
                                  onChanged: (_) => setState(() {}),
                                  validator: (v) {
                                    final n = cents(v ?? '');
                                    return n == null ||
                                            ((supplier || !modern) && n > net)
                                        ? 'أدخل دفعة صحيحة لا تتجاوز صافي فاتورة المورد'
                                        : null;
                                  },
                                ),
                              ),
                            if (hasPayment) ...[
                              DropdownButtonFormField<String>(
                                initialValue: methods.containsKey(method)
                                    ? method
                                    : 'Cash',
                                items: methods.entries
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e.key,
                                        child: Text(e.value),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) => setState(() => method = v!),
                                decoration: const InputDecoration(
                                  labelText: 'وسيلة الدفع',
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (method != 'Cash')
                                field(
                                  reference,
                                  'رقم المرجع',
                                  required: !modern,
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
                                onChanged: (v) => setState(() => waiting = v!),
                              ),
                            if (modern &&
                                hasPayment &&
                                method == 'Cash' &&
                                !supplier)
                              Surface(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Text(
                                      'حساب الباقي',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
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
                                      'الباقي: ${money(((cents(handed.text) ?? 0) - requestedPayment).clamp(0, 99999999900) / 100)}',
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
                              field(
                                counterparty,
                                kind == 'Payment'
                                    ? 'اسم الدافع / المستلم'
                                    : 'اسم مستلم البضاعة',
                                max: 120,
                              ),
                            if (isInvoice)
                              field(
                                invoice,
                                'رقم الفاتورة (اختياري)',
                                max: 100,
                              ),
                            if (modern && isInvoice)
                              Wrap(
                                spacing: 6,
                                children: [
                                  for (final preset in [
                                    'مواد تموينية',
                                    'خضار وفواكه',
                                    'مخبوزات',
                                    'أصناف متنوعة',
                                  ])
                                    ActionChip(
                                      label: Text(preset),
                                      onPressed: () => note.text = preset,
                                    ),
                                ],
                              ),
                            field(
                              note,
                              'وصف الحركة (اختياري)',
                              lines: 3,
                              max: 2000,
                            ),
                            Row(
                              children: [
                                Expanded(child: Text('التاريخ: ${day(when)}')),
                                IconButton(
                                  tooltip: 'تغيير التاريخ',
                                  onPressed: () async {
                                    final d = await showDatePicker(
                                      context: context,
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime.now(),
                                      initialDate: when,
                                    );
                                    if (d != null) {
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
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (modern && party != null)
                        Surface(
                          color: const Color(0xFFF1F2F8),
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
                                    Text('صافي الفاتورة: ${money(net / 100)}'),
                                ],
                              );
                            },
                          ),
                        ),
                      if (modern && !supplier && kind == 'Payment' && pending == null)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'فتح مسودة إيصال عبر واتساب بعد الحفظ',
                          ),
                          subtitle: const Text('تراجع الرسالة وترسلها بنفسك.'),
                          value: receipt,
                          onChanged: (v) => setState(() => receipt = v!),
                        ),
                      if (pending == null)
                        OutlinedButton.icon(
                          onPressed: busy ? null : dictate,
                          icon: Icon(listening ? Icons.stop : Icons.mic_none),
                          label: Text(
                            listening ? 'إيقاف التسجيل' : 'إملاء وصف الحركة',
                          ),
                        ),
                      const SizedBox(height: 12),
                      const Text(
                        'راجع التفاصيل قبل الحفظ. لا يُسجّل الصوت أي حركة تلقائياً.',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                      const SizedBox(height: 20),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      BusyButton(
                        label: pending == null
                            ? 'حفظ الحركة'
                            : 'إعادة محاولة حفظ نفس الحركة',
                        busy: busy,
                        onPressed: save,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
  );
}
