import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:uuid/uuid.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/ledger.dart';
import '../core/supplier_invoice_note.dart';
import '../services/receipts.dart';
import 'invoice_items.dart';
import 'supplier_invoice_items.dart';
import '../core/session.dart';
import '../core/storage.dart';
import '../ui/theme.dart';
import '../ui/design.dart';
import '../ui/widgets.dart';
import '../ui/party_lookup_field.dart';
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
      paid = TextEditingController(),
      note = TextEditingController(),
      reference = TextEditingController(),
      invoice = TextEditingController(),
      discount = TextEditingController(text: '0'),
      counterparty = TextEditingController(),
      handed = TextEditingController();
  final lines = <InvoiceLine>[];
  final supplierPackCounts = <String, int>{};
  bool _updatingSupplierNote = false;
  bool _supplierNoteEdited = false;

  void _noteChangedByUser() {
    if (!_updatingSupplierNote && supplier && isInvoice) {
      _supplierNoteEdited = true;
    }
  }

  void _refreshSupplierInvoiceNote() {
    if (!supplier || !isInvoice || !itemMode || _supplierNoteEdited || pending != null) return;
    final generated = supplierInvoiceDescription(
      invoiceNumber: invoice.text,
      lines: lines,
      packCounts: supplierPackCounts,
    );
    if (generated == note.text) return;
    _updatingSupplierNote = true;
    note.text = generated;
    _updatingSupplierNote = false;
  }

  void _resetSupplierInvoiceNote() {
    _supplierNoteEdited = false;
    _refreshSupplierInvoiceNote();
    setState(() {});
  }
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
    _refreshSupplierInvoiceNote();
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
  bool get isCustomerDebt => kind == 'Debt' && !supplier;
  bool get isCustomerPayment => kind == 'Payment' && !supplier;
  bool get timestampOnSave => isInvoice || kind == 'Payment';
  bool get hasPayment =>
      kind == 'Payment' || (isInvoice && (cents(paid.text) ?? 0) > 0);
  String get supplierInvoiceNote {
    final body = note.text.trim();
    if (!supplier || !isInvoice || !itemMode || !_supplierNoteEdited) {
      return body;
    }
    // An edited description must still keep the package sizes that the
    // backend's LedgerItem schema cannot store in a dedicated column.
    final packages = [
      for (final item in lines)
        if (const {'كرتونة', 'صندوق', 'طرد', 'شوال'}.contains(item.unit))
          '${item.name}: ${supplierPackCounts[item.id] ?? 12} عبوة في ${item.unit}',
    ];
    if (packages.isEmpty) return body;
    return [body, 'تفاصيل العبوات: ${packages.join('؛ ')}']
        .where((line) => line.isNotEmpty).join('\n');
  }
  @override
  void initState() {
    super.initState();
    party = widget.party;
    kind = widget.kind;
    supplier =
        widget.supplier || kind == 'Purchase' || party?['kind'] == 'Supplier';
    // The sender of a customer transfer might be someone other than the customer.
    counterparty.text = kind == 'Payment' || supplier ? '' : (party?['name'] ?? '');
    note.addListener(_noteChangedByUser);
    invoice.addListener(_refreshSupplierInvoiceNote);
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
        _supplierNoteEdited = true;
        note.text = data['note'] ?? '';
        reference.text = data['reference'] ?? '';
        invoice.text = data['invoiceNumber'] ?? '';
        discount.text = '${data['discount'] ?? 0}';
        counterparty.text = data['counterpartyName'] ?? '';
        // Restore older drafts that kept the transfer sender in reference.
        if (data['kind'] == 'Payment' &&
            data['method'] != 'Cash' &&
            counterparty.text.trim().isEmpty) {
          counterparty.text = data['reference'] ?? '';
        }
        waiting = data['pendingConfirmation'] == true;
        lines.addAll(
          (data['items'] as List? ?? []).map(
            (p) => InvoiceLine.fromJson(Map<String, dynamic>.from(p)),
          ),
        );
        itemMode = lines.isNotEmpty;
        // Recover pack counts from the human-readable note in older drafts.
        for (final item in lines) {
          if (!const {'كرتونة', 'صندوق', 'طرد', 'شوال'}.contains(item.unit)) continue;
          final pattern = RegExp('${RegExp.escape(item.name)}.*?(\\d+) عبوة');
          final count = int.tryParse(pattern.firstMatch(note.text)?.group(1) ?? '');
          if (count != null && count > 0) supplierPackCounts[item.id] = count;
        }
        method = data['method'];
        when = DateTime.parse(data['occurredAt']).toLocal();
        party = await s.api.get('/api/parties/${data['partyId']}');
        supplier = party?['kind'] == 'Supplier';
      }
    } catch (e) {
      error = '$e';
    } finally {
      if (pending == null && supplier && isInvoice && modern) {
        itemMode = true;
        _refreshSupplierInvoiceNote();
      }
      if (pending == null &&
          widget.initialProduct != null &&
          mounted &&
          modern &&
          !supplier) {
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
      if (supplier && isInvoice && itemMode) {
        if (lines.isEmpty) {
          message(context, 'أضف صنفًا واحدًا على الأقل أو اختر المبلغ الإجمالي السريع.');
          return;
        }
        if (lines.any((line) => line.name.trim().isEmpty ||
            line.name.trim().length > 160 || line.price <= 0 ||
            line.quantity <= 0 || line.unit.trim().isEmpty)) {
          message(context, 'تأكد من اسم كل صنف وكميته وسعر الجملة قبل الحفظ.');
          return;
        }
      }
      if (!form.currentState!.validate()) return;
      if (supplier && isInvoice && itemMode && supplierInvoiceNote.length > 2000) {
        message(context, 'بيان الفاتورة طويل جدًا. اختصر الملاحظات أو عدد الأصناف.');
        return;
      }
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
              ? lines.map((p) => supplier
                  ? p.toSupplierInvoiceJson()
                  : p.toJson()).toList()
              : [],
        },
        'method': hasPayment ? method : 'Cash',
        'occurredAt': (timestampOnSave ? DateTime.now() : when)
            .toUtc()
            .toIso8601String(),
        // Supplier payments intentionally have no reference/sender field.
        // Existing customer transfer reports still use reference for sender.
        'reference': supplier && kind == 'Payment'
            ? ''
            : isCustomerPayment && method != 'Cash'
                ? counterparty.text.trim()
                : (hasPayment ? reference.text.trim() : ''),
        'invoiceNumber': invoice.text.trim().isEmpty
            ? null
            : invoice.text.trim(),
        'note': supplier && isInvoice && itemMode
            ? supplierInvoiceNote
            : note.text.trim(),
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

  Widget _partySelector() {
    if (widget.party != null || pending != null) {
      return ListTile(
        tileColor: const Color(0xFFF7F8FB),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: const Icon(Icons.person_outline),
        title: Text('${party?['name'] ?? 'اختر الزبون'}'),
        trailing: const Icon(Icons.lock_outline),
      );
    }
    return PartyLookupField(
      key: ValueKey('party-search-$supplier'),
      label: supplier ? 'المورد' : 'الزبون',
      selected: party,
      enabled: !busy,
      search: (text) async {
        final response = await Scope.of(context).api.get(
          supplier ? '/api/suppliers' : '/api/customers',
          query: {'search': text, 'sort': 'name', 'page': 1, 'size': 30},
        );
        return (response['items'] as List)
            .map((p) => Map<String, dynamic>.from(p as Map)).toList();
      },
      onSelected: (chosen) => setState(() {
        party = chosen;
        if (kind != 'Payment' && !supplier) {
          counterparty.text = '${chosen?['name'] ?? ''}';
        } else {
          counterparty.clear();
        }
      }),
    );
  }

  Widget _supplierInvoiceNumber() => TextFormField(
    controller: invoice,
    maxLength: 100,
    decoration: const InputDecoration(
      labelText: 'رقم الفاتورة',
      hintText: 'اختياري',
      counterText: '',
    ),
  );

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
                ? 'تسجيل فاتورة مورد (بضاعة واردة)'
                : 'تسجيل مشتريات (دين)',
            style: appText(supplier && isInvoice ? 14 : 16, weight: FontWeight.w900),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            supplier && isInvoice
                ? 'أدخل الأصناف والكميات لمطابقة إجمالي الفاتورة تلقائيًا'
                : '${party?['name'] ?? 'دفتر دين'} · حفظ ومزامنة البيانات',
            style: appText(10, color: muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: (isCustomerDebt || kind == 'Payment')
          ? [
              IconButton(
                key: Key(kind == 'Payment'
                    ? (supplier
                        ? 'supplier-payment-description-microphone'
                        : 'payment-description-microphone')
                    : 'debt-description-microphone'),
                tooltip: listening ? 'إيقاف الإملاء الصوتي' : 'إملاء وصف الحركة',
                onPressed: busy || pending != null || restoring
                    ? null
                    : dictate,
                icon: Icon(
                  listening ? Icons.stop_circle_outlined : Icons.mic_none,
                  color: listening ? orange : navy,
                ),
              ),
            ]
          : null,
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
          child: Row(
            children: [
              Expanded(child: BusyButton(
            label: pending != null
                ? 'إعادة محاولة حفظ نفس الحركة'
                : kind == 'Payment'
                ? (supplier ? 'اعتماد وحفظ سداد المورد ✓' : 'تأكيد وحفظ الدفعة في دفتر دين ✓')
                : kind == 'Return'
                ? 'تأكيد وحفظ المرتجع ✓'
                : supplier
                ? 'اعتماد وحفظ فاتورة المورد ✓'
                : 'تأكيد وحفظ المشتريات في دفتر دين ✓',
            background: kind == 'Payment' ? navy : orange,
            busy: busy,
            onPressed: restoring ? null : save,
          )),
              if (supplier && isInvoice) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  decoration: BoxDecoration(
                    color: navy,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    displayMoney(gross / 100),
                    style: appText(11, color: Colors.white, weight: FontWeight.w800),
                  ),
                ),
              ],
            ],
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
                      // The customer-payment screen never offers a supplier
                      // switch. Supplier settlement remains in its separate
                      // flow from the suppliers section.
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
                            if (supplier && isInvoice)
                              LayoutBuilder(
                                builder: (context, dimensions) =>
                                    dimensions.maxWidth >= 295
                                        ? Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(flex: 2, child: _partySelector()),
                                              const SizedBox(width: 10),
                                              Expanded(child: _supplierInvoiceNumber()),
                                            ],
                                          )
                                        : Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              _partySelector(),
                                              const SizedBox(height: 10),
                                              _supplierInvoiceNumber(),
                                            ],
                                          ),
                              )
                            else
                              _partySelector(),
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
                                items: {
                                  false: supplier
                                      ? 'مبلغ إجمالي سريع'
                                      : 'المسار السريع (مبلغ مباشر)',
                                  true: supplier
                                      ? 'تفصيل الأصناف والأسعار'
                                      : 'اختيار أصناف (بالقطعة/الوزن)',
                                },
                                selected: itemMode,
                                onSelected: (v) {
                                  setState(() {
                                    itemMode = v;
                                    if (!v && supplier && isInvoice && !_supplierNoteEdited) {
                                      _updatingSupplierNote = true;
                                      note.clear();
                                      _updatingSupplierNote = false;
                                    }
                                  });
                                  if (itemMode) itemsChanged();
                                },
                              ),
                              const SizedBox(height: 12),
                              if (itemMode)
                                supplier && isInvoice
                                    ? SupplierInvoiceItems(
                                        lines: lines,
                                        onChanged: itemsChanged,
                                        packCounts: supplierPackCounts,
                                        onPackCountChanged: (id, count) {
                                          supplierPackCounts[id] = count;
                                          _refreshSupplierInvoiceNote();
                                        },
                                      )
                                    : InvoiceItems(
                                        lines: lines,
                                        purchase: supplier,
                                        onChanged: itemsChanged,
                                      ),
                            ],
                            if (!supplier || !isInvoice || !itemMode)
                              Surface(
                                child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    supplier && isInvoice
                                        ? 'مبلغ إجمالي سريع'
                                        : 'المبلغ الإجمالي بالشيكل (₪):',
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
                            if (isInvoice && !supplier)
                              Surface(
                                child: ExpansionTile(
                                  initiallyExpanded: (cents(paid.text) ?? 0) > 0,
                                  maintainState: true,
                                  tilePadding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 8,
                                  ),
                                  childrenPadding: const EdgeInsets.fromLTRB(
                                    12,
                                    12,
                                    12,
                                    20,
                                  ),
                                  shape: const Border(),
                                  collapsedShape: const Border(),
                                  title: Text(
                                    'دفعة مع المشتريات (اختياري)',
                                    style: appText(
                                      13,
                                      weight: FontWeight.w800,
                                    ),
                                  ),
                                  children: [
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        'المبلغ المدفوع من الزبون — شيكل',
                                        style: appText(
                                          12,
                                          weight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      key: const Key('customer-debt-paid-now'),
                                      controller: paid,
                                      textAlign: TextAlign.right,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        hintText: 'أدخل مبلغ الدفعة إن وُجد',
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 16,
                                        ),
                                      ),
                                      validator: (value) {
                                        if (value == null ||
                                            value.trim().isEmpty) {
                                          return null;
                                        }
                                        return cents(value) == null
                                            ? 'أدخل مبلغًا صحيحًا بالشيكل'
                                            : null;
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            if (hasPayment && !(supplier && isInvoice))
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
                                    if (method != 'Cash' && isCustomerPayment) ...[
                                      const SizedBox(height: 12),
                                      field(
                                        counterparty,
                                        'اسم صاحب الحوالة (اختياري)',
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
                            if (supplier && isInvoice)
                              Surface(
                                color: const Color(0xFFECFDF5),
                                child: ExpansionTile(
                                  key: const Key('supplier-invoice-partial-payment'),
                                  initiallyExpanded: (cents(paid.text) ?? 0) > 0,
                                  maintainState: true,
                                  tilePadding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  childrenPadding: const EdgeInsets.fromLTRB(
                                    4, 28, 4, 14,
                                  ),
                                  title: Text(
                                    'دفعت جزءًا من الفاتورة للمورد الآن؟',
                                    style: appText(12, weight: FontWeight.w900, color: green),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'سجّل المبلغ المدفوع ليُخصم من صافي مستحقات المورد.',
                                      style: appText(10, color: secondaryText),
                                    ),
                                  ),
                                  children: [
                                    if (modern) ...[
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          'خصم على الفاتورة (₪) — اختياري',
                                          style: appText(11, weight: FontWeight.w800),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextFormField(
                                        controller: discount,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        textAlign: TextAlign.right,
                                        decoration: const InputDecoration(
                                          hintText: '0.00',
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 18,
                                          ),
                                        ),
                                        validator: (value) {
                                          final raw = (value ?? '').trim();
                                          final n = raw.isEmpty ? 0 : cents(raw);
                                          return n == null || n < 0 || n >= gross
                                              ? 'الخصم يجب أن يكون أقل من قيمة الفاتورة'
                                              : null;
                                        },
                                      ),
                                      const SizedBox(height: 22),
                                    ],
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        'المبلغ المدفوع الآن (₪)',
                                        style: appText(11, weight: FontWeight.w800),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      key: const Key('supplier-invoice-paid-amount'),
                                      controller: paid,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      textAlign: TextAlign.right,
                                      decoration: const InputDecoration(
                                        hintText: '0.00',
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 18,
                                        ),
                                      ),
                                      validator: (value) {
                                        final raw = (value ?? '').trim();
                                        final amount = raw.isEmpty ? 0 : cents(raw);
                                        return amount == null || amount < 0 || amount > net
                                            ? 'الدفعة لا يجوز أن تتجاوز صافي الفاتورة'
                                            : null;
                                      },
                                    ),
                                    const SizedBox(height: 22),
                                    // Keep all three shortcuts on ONE row, with
                                    // two-line labels allowed on small phones.
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            key: const Key('supplier-pay-half'),
                                            onPressed: () => paid.text = decimalMoney(
                                              (net.clamp(0, 99999999900).toInt() + 1) ~/ 2,
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(0, 60),
                                              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
                                            ),
                                            child: Text(
                                              'دفع النصف 50%',
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              softWrap: true,
                                              style: appText(10, weight: FontWeight.w800, height: 1.25),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: OutlinedButton(
                                            key: const Key('supplier-pay-full'),
                                            onPressed: () => paid.text = decimalMoney(
                                              net.clamp(0, 99999999900).toInt(),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(0, 60),
                                              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
                                            ),
                                            child: Text(
                                              'دفع كامل الفاتورة',
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              softWrap: true,
                                              style: appText(10, weight: FontWeight.w800, height: 1.25),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: OutlinedButton(
                                            key: const Key('supplier-pay-later'),
                                            onPressed: () => paid.clear(),
                                            style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(0, 60),
                                              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
                                            ),
                                            child: Text(
                                              'آجل بالكامل',
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              softWrap: true,
                                              style: appText(10, weight: FontWeight.w800, height: 1.25),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (hasPayment) ...[
                                      const SizedBox(height: 16),
                                      Text('وسيلة السداد', style: appText(11, weight: FontWeight.w800)),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          for (final m in methods.entries)
                                            ChoiceChip(
                                              label: Text(m.value),
                                              selected: method == m.key,
                                              onSelected: (_) => setState(() => method = m.key),
                                            ),
                                        ],
                                      ),
                                    ],
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
                            if (modern && isInvoice && !supplier)
                              Surface(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      supplier
                                          ? 'اسم المستلم داخل المحل (اختياري):'
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
                                      supplier
                                          ? 'مين استلم البضاعة داخل المحل؟'
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
                                    isInvoice
                                        ? (supplier
                                            ? 'بيان الفاتورة في السجل (اختياري):'
                                            : 'شو اشترى؟ / ملاحظات الفاتورة (اختياري):')
                                        : 'البيان / الملاحظة (اختياري):',
                                    style: appText(12, weight: FontWeight.w800),
                                  ),
                                  if (supplier && isInvoice && itemMode) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Expanded(child: Text(
                                          _supplierNoteEdited
                                              ? 'تم تعديل البيان يدويًا؛ لن يُستبدل تلقائيًا'
                                              : 'يُولّد تلقائيًا من الأصناف ورقم الفاتورة',
                                          style: appText(10, color: secondaryText),
                                        )),
                                        TextButton(
                                          onPressed: _resetSupplierInvoiceNote,
                                          child: const Text('توليد من جديد'),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  field(
                                    note,
                                    supplier && isInvoice
                                        ? 'تفاصيل البضاعة المستلمة أو ملاحظة'
                                        : 'وصف الحركة (اختياري)',
                                    lines: supplier && isInvoice ? 2 : 3,
                                    max: 2000,
                                  ),
                                  if (timestampOnSave)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Text(
                                        'يُحفظ التاريخ والوقت تلقائيًا عند تسجيل الحركة.',
                                        style: appText(11, color: secondaryText),
                                      ),
                                    ),
                                  if (!timestampOnSave) ...[
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
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (supplier && isInvoice && modern)
                        Surface(
                          color: navy,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('إجمالي قيمة البضاعة (الفاتورة)',
                                      style: appText(11, color: Colors.white)),
                                  Text(displayMoney(gross / 100),
                                      style: appText(16, weight: FontWeight.w900, color: Colors.white)),
                                ],
                              ),
                              if ((cents(discount.text) ?? 0) > 0)
                                _SupplierInvoiceSummaryRow(
                                  'الخصم',
                                  '- ${displayMoney((cents(discount.text) ?? 0) / 100)}',
                                ),
                              if ((cents(paid.text) ?? 0) > 0)
                                _SupplierInvoiceSummaryRow(
                                  'المبلغ المدفوع الآن',
                                  '- ${displayMoney((cents(paid.text) ?? 0) / 100)}',
                                ),
                              const Divider(color: Colors.white38, height: 22),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('الصافي المضاف لذمة المورد',
                                      style: appText(12, color: Colors.white, weight: FontWeight.w900)),
                                  Text(displayMoney(((net - actualPayment).clamp(0, 99999999900)) / 100),
                                      style: appText(17, color: Colors.white, weight: FontWeight.w900)),
                                ],
                              ),
                              if (party != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'رصيد المورد بعد الحفظ: ${displayMoney((amountCents(party!['balance']) + net - actualPayment) / 100)}',
                                  style: appText(10, color: const Color(0xFFDBDEFF)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      if (modern && party != null && !(supplier && isInvoice))
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


class _SupplierInvoiceSummaryRow extends StatelessWidget {
  const _SupplierInvoiceSummaryRow(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 7),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: appText(10, color: const Color(0xFFDBDEFF))),
        Text(value, style: appText(11, color: Colors.white)),
      ],
    ),
  );
}
