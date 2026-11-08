import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';

import '../core/format.dart';
import '../core/session.dart';
import '../services/export.dart';
import '../services/subscription_contact.dart';
import '../ui/theme.dart';
import '../ui/design.dart';
import 'sync_center.dart';
import '../ui/widgets.dart';

class Plans extends StatelessWidget {
  const Plans({super.key, required this.selected, required this.select});
  final int selected;
  final ValueChanged<int> select;
  @override
  Widget build(BuildContext c) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final i in [1, 3]) ...[
        if (i == 3) const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            selected: selected == i,
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => select(i),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: selected == i ? lavender : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected == i ? navy : lineColor,
                    width: selected == i ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            i == 1 ? 'شهر واحد' : '3 أشهر',
                            style: appText(12, weight: FontWeight.w900),
                          ),
                        ),
                        Icon(
                          selected == i
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: navy,
                          size: 18,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FittedBox(child: amount(i == 1 ? 60 : 150, size: 30)),
                    Text(
                      i == 1 ? 'شيكل / شهر' : 'شيكل / 3 أشهر',
                      style: appText(10, color: secondaryText),
                    ),
                    const SizedBox(height: 12),
                    SoftTag(
                      i == 1 ? 'مرونة شهرية' : 'الأوفر · خصم 30 ₪',
                      color: i == 1 ? navy : orange,
                      background: i == 1 ? lavender : paleOrange,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

class AccountHelp extends StatefulWidget {
  const AccountHelp({super.key, this.reset = false});
  final bool reset;
  @override
  State<AccountHelp> createState() => _AccountHelpState();
}

class _AccountHelpState extends State<AccountHelp> {
  int selected = 3, step = 0;
  bool trial = true, passwordHidden = true, busy = false;
  String? error, receiptBase64, receiptContentType;
  final name = TextEditingController(),
      phone = TextEditingController(),
      owner = TextEditingController(),
      password = TextEditingController(),
      sender = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    owner.dispose();
    password.dispose();
    sender.dispose();
    super.dispose();
  }

  Future<void> submitRegistration() async {
    if (busy) return;
    if (!trial && sender.text.trim().isEmpty) {
      setState(() => error = 'اسم صاحب الحوالة مطلوب');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final s = Scope.of(context);
      final result = await s.api.registerShop({
        'shopName': name.text.trim(),
        'ownerName': owner.text.trim(),
        'phoneNumber': phoneNumber(phone.text),
        'password': password.text,
        'freeTrial': trial,
        'months': selected,
        'senderName': trial ? null : sender.text.trim(),
        'destination': 'bank',
        'receiptImageBase64': receiptBase64,
        'receiptContentType': receiptContentType,
      });
      if (!mounted) return;
      if (trial) {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => _TrialActivatedScreen(
            start: '${result['trialStartedAt']}',
            end: '${result['trialEndsAt']}',
            phone: phoneNumber(phone.text)!,
            password: password.text,
          ),
        ));
      } else {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => _PendingActivationPreview(
            shop: name.text.trim(), owner: owner.text.trim(),
            months: selected, sender: sender.text.trim(),
          ),
        ));
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String get request => widget.reset
      ? 'أحتاج لاستعادة الدخول للرقم ${phoneNumber(phone.text)}'
      : [
          if (trial)
            'مرحباً، أرغب بفتح حساب جديد لمحل ${name.text.trim()} وتجربة مجانية لمدة 14 يوماً.\nرقم الجوال: ${phoneNumber(phone.text)}'
          else
            subscriptionRequestText(
              shopName: name.text,
              phone: phoneNumber(phone.text),
              months: selected,
            ),
          if (owner.text.trim().isNotEmpty)
            'اسم صاحب المحل: ${owner.text.trim()}',
          if (!trial && sender.text.trim().isNotEmpty)
            'اسم صاحب الحوالة: ${sender.text.trim()}',
        ].join('\n');
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const BrandHeader(back: true),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (!widget.reset) ...[
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Column(
                              children: [
                                Container(
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: i <= step ? orange : lineColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  [
                                    'بيانات المحل',
                                    'اختر الخطة',
                                    'الدفع والتفعيل',
                                  ][i],
                                  style: appText(
                                    10,
                                    color: i == step ? navy : muted,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),
                ],
                Text(
                  widget.reset
                      ? 'نساعدك ترجع لحسابك'
                      : [
                          'خلّينا نتعرّف على محلك',
                          'ابدأ بالطريقة التي تناسبك',
                          'تحويل رسوم الاشتراك وتفعيل المحل',
                        ][step],
                  style: appText(22, weight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.reset
                      ? 'تواصل مع إدارة الخدمة لاستعادة الوصول إلى حسابك.'
                      : [
                          'أدخل بيانات المحل ورقم الجوال الذي ستستخدمه للدخول.',
                          'جرّب دفتر دين 14 يوماً مجاناً، أو اختر اشتراكك.',
                          'راجع بيانات تحويل الاشتراك. يتطلب التفعيل موافقة الإدارة.',
                        ][step],
                  style: appText(12, color: secondaryText),
                ),
                const SizedBox(height: 24),
                if (widget.reset || step == 0)
                  Form(
                    key: form,
                    child: Column(
                      children: [
                        if (!widget.reset) ...[
                          field(owner, 'اسم صاحب المحل', required: true),
                          field(name, 'اسم المحل', required: true),
                        ],
                        if (!widget.reset)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: TextFormField(
                              controller: password,
                              obscureText: passwordHidden,
                              decoration: InputDecoration(
                                labelText: 'كلمة المرور',
                                suffixIcon: IconButton(
                                  onPressed: () => setState(() => passwordHidden = !passwordHidden),
                                  icon: Icon(passwordHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                ),
                              ),
                              validator: (v) => (v?.length ?? 0) < 12
                                  ? 'استخدمي كلمة مرور من 12 حرفاً على الأقل'
                                  : null,
                            ),
                          ),
                        field(
                          phone,
                          'رقم الجوال',
                          keyboard: TextInputType.phone,
                          validator: (v) => phoneNumber(v ?? '') == null
                              ? 'أدخل رقم جوال صحيحاً'
                              : null,
                        ),
                      ],
                    ),
                  ),
                if (!widget.reset && step == 1) ...[
                  InkWell(
                    onTap: () => setState(() => trial = true),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: trial ? green : const Color(0xFFA7F3D0),
                          width: trial ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.card_giftcard_outlined,
                            color: green,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'جرّب مجاناً لمدة 14 يوم',
                                  style: appText(
                                    14,
                                    color: green,
                                    weight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  'تبدأ التجربة عند إنشاء حسابك',
                                  style: appText(11, color: green),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            trial
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: green,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Heading('خطط الاشتراك'),
                  Plans(
                    selected: trial ? 0 : selected,
                    select: (v) => setState(() {
                      selected = v;
                      trial = false;
                    }),
                  ),
                ],
                if (!widget.reset && step == 2) ...[
                  Surface(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(name.text.trim(), style: appText(17, weight: FontWeight.w900)),
                      Text('${owner.text.trim()} · ${phoneNumber(phone.text) ?? phone.text}', style: appText(12, color: secondaryText)),
                      const SizedBox(height: 12),
                      SoftTag(trial ? 'تجربة مجانية · 14 يوماً' : selected == 1 ? 'شهر · 60 ₪' : '3 أشهر · 150 ₪'),
                    ],
                  )),
                  const SizedBox(height: 16),
                  if (trial) ...[
                    const _TrialInformation(),
                  ] else ...[
                    _PaymentInstructions(sender: sender, onReceipt: (encoded, mime) {
                      receiptBase64 = encoded;
                      receiptContentType = mime;
                    }),
                    const SizedBox(height: 12),
                    Text('بعد تسجيل الطلب على الخادم يبقى قيد المراجعة حتى يؤكد الأدمن وصول الحوالة.', style: appText(11, color: secondaryText)),
                  ],
                ],
                const SizedBox(height: 24),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(error!, style: const TextStyle(color: Colors.red)),
                  ),
                BusyButton(
                  busy: busy,
                  label: widget.reset || step == 2
                      ? (widget.reset ? 'طلب استعادة الحساب' : trial ? 'طلب بدء تجربة مجانية' : 'أرسلت التحويل — إرسال طلب التفعيل')
                      : 'متابعة ←',
                  onPressed: () async {
                    if ((widget.reset || step == 0) &&
                        !form.currentState!.validate()) {
                      return;
                    }
                    if (widget.reset) {
                      await contact(context, request);
                    } else if (step == 2) {
                      await submitRegistration();
                    } else {
                      setState(() => step++);
                    }
                  },
                ),
                if (!widget.reset && step > 0)
                  TextButton(
                    onPressed: () => setState(() => step--),
                    child: const Text('رجوع للخطوة السابقة'),
                  ),
                const SizedBox(height: 20),
                Text(
                  widget.reset
                      ? 'لن نطلب كلمة مرورك في رسالة.'
                      : 'كلمة المرور تحفظ في الخادم بصورة مشفّرة ولا تُرسل للإدارة أو واتساب.',
                  textAlign: TextAlign.center,
                  style: appText(11, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Payment instructions matching the supplied reference. Only known bank
/// details are shown; wallet destinations require configuration by backend.
class _PaymentInstructions extends StatefulWidget {
  const _PaymentInstructions({required this.sender, required this.onReceipt});
  final TextEditingController sender;
  final void Function(String?, String?) onReceipt;
  @override
  State<_PaymentInstructions> createState() => _PaymentInstructionsState();
}

class _PaymentInstructionsState extends State<_PaymentInstructions> {
  int destination = 0;
  String? chosenImage;
  Future<void> chooseReceipt() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1600, imageQuality: 75);
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        if (mounted) message(context, 'يجب ألا تتجاوز الصورة 2 ميجابايت');
        return;
      }
      final mime = image.name.toLowerCase().endsWith('.png')
        ? 'image/png' : 'image/jpeg';
      if (!mounted) return;
      widget.onReceipt(base64Encode(bytes), mime);
      setState(() => chosenImage = image.name);
    } catch (e) { if (mounted) message(context, '$e'); }
  }
  @override
  Widget build(BuildContext context) => Surface(child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('تحويل رسوم الاشتراك وتفعيل المحل', style: appText(17, weight: FontWeight.w900)),
      const SizedBox(height: 8),
      Text('أولاً: اختر وجهة التحويل', style: appText(13, weight: FontWeight.w800)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (i, label) in [(0, 'بنك فلسطين'), (1, 'محفظتي PalPay'), (2, 'جوال بي')])
          ChoiceChip(label: Text(label), selected: destination == i, onSelected: i == 0 ? (_) => setState(() => destination = i) : null),
      ]),
      const SizedBox(height: 12),
      if (destination == 0) ...[
        _copyLine(context, 'صاحب الحساب المستلم', 'لؤي محمد أبو زعنونة'),
        _copyLine(context, 'رقم الجوال', '0594301646'),
        _copyLine(context, 'IBAN', 'PS92PALS045310978160993000000'),
      ] else
        Text('لم تُضف الإدارة بيانات التحويل لهذه المحفظة بعد. اختر بنك فلسطين أو تواصل مع الإدارة.', style: appText(12, color: secondaryText)),
      const SizedBox(height: 14),
      Text('ثانياً: اسم المرسل (صاحب الحساب المحوّل)', style: appText(12, weight: FontWeight.w800)),
      TextField(controller: widget.sender, decoration: const InputDecoration(hintText: 'اسم صاحب الحوالة')),
      const SizedBox(height: 8),
      Text('ثالثاً: صورة إشعار التحويل (اختياري)', style: appText(12, weight: FontWeight.w800)),
      OutlinedButton.icon(onPressed: chooseReceipt,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: Text(chosenImage == null ? 'إرفاق صورة إشعار التحويل' : 'تم اختيار الصورة · تغيير')),
      if (chosenImage != null)
        Text(chosenImage!, style: appText(11, color: secondaryText)),
    ],
  ));
  Widget _copyLine(BuildContext context, String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: lavender, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: appText(11, color: secondaryText)),
          SelectableText(value, textDirection: title == 'صاحب الحساب المستلم' ? TextDirection.rtl : TextDirection.ltr, style: appText(12, weight: FontWeight.w900)),
        ])),
        IconButton(tooltip: 'نسخ $title', onPressed: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (context.mounted) message(context, 'تم النسخ');
        }, icon: const Icon(Icons.copy_outlined)),
      ]),
    ),
  );
}

class _TrialActivatedScreen extends StatelessWidget {
  const _TrialActivatedScreen({required this.start, required this.end,
    required this.phone, required this.password});
  final String start, end, phone, password;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تم تفعيل التجربة المجانية')),
    body: Width(child: ListView(padding: const EdgeInsets.all(20), children: [
      const Icon(Icons.check_circle_outline_rounded, color: green, size: 74),
      const SizedBox(height: 20),
      Text('حساب محلك جاهز!', textAlign: TextAlign.center,
        style: appText(25, weight: FontWeight.w900)),
      const SizedBox(height: 12),
      Text('يمكنك استخدام دفتر دين مجاناً لمدة 14 يوماً.',
        textAlign: TextAlign.center),
      const SizedBox(height: 18),
      Surface(child: Column(children: [
        Text('تاريخ البدء: ${start.split('T').first}'),
        Text('تاريخ الانتهاء: ${end.split('T').first}'),
      ])),
      const SizedBox(height: 18),
      BusyButton(label: 'البدء باستخدام التطبيق', onPressed: () async {
        try {
          await Scope.of(context).login(phone, password);
        } catch (e) { if (context.mounted) message(context, '$e'); }
      }),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: () async {
        try {
          await Scope.of(context).loginForWorkerSetup(phone, password);
        } catch (e) { if (context.mounted) message(context, '$e'); }
      }, child: const Text('إضافة عاملين')),
    ])),
  );
}

class _TrialInformation extends StatelessWidget {
  const _TrialInformation();
  @override
  Widget build(BuildContext context) => Surface(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('تجربة مجانية لمدة 14 يوماً', style: appText(18, weight: FontWeight.w900, color: green)),
      const Text('سيظهر تاريخ البداية والانتهاء فور تأكيد إنشاء الحساب من الخادم.'),
      const SizedBox(height: 10),
      Text('بعد إنشاء الحساب ستظهر صفحة التأكيد مع زري البدء وإضافة العاملين.',
        style: appText(11, color: secondaryText)),
    ],
  ));
}

/// Status preview; never claim that the server received or approved payment.
class _PendingActivationPreview extends StatelessWidget {
  const _PendingActivationPreview({required this.shop, required this.owner, required this.months, required this.sender});
  final String shop, owner, sender;
  final int months;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('متابعة طلب التفعيل')),
    body: Width(child: ListView(padding: const EdgeInsets.all(20), children: [
      const Icon(Icons.hourglass_empty_rounded, color: orange, size: 52),
      const SizedBox(height: 16),
      Text('طلب اشتراك قيد المراجعة', textAlign: TextAlign.center, style: appText(23, weight: FontWeight.w900)),
      const SizedBox(height: 10),
      Text('تم حفظ طلبك على الخادم، لكن لم يتم تأكيد وصول الحوالة بعد. ستفعّل إدارة الخدمة اشتراكك بعد التحقق.', textAlign: TextAlign.center, style: appText(12, color: secondaryText)),
      const SizedBox(height: 20),
      Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('المحل: $shop'),
        Text('المالك: $owner'),
        Text('الخطة: ${months == 1 ? 'شهر · 60 ₪' : '3 أشهر · 150 ₪'}'),
        if (sender.isNotEmpty) Text('اسم المرسل: $sender'),
        const SizedBox(height: 10),
        const SoftTag('بانتظار التحقق من إدارة الخدمة'),
      ])),
      OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('تعديل معلومات التحويل')),
    ])),
  );
}

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, this.gate = false});
  final bool gate;
  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  int selected = 3;
  bool busy = false;
  String? activationStatus, receiptBase64, receiptContentType;
  final sender = TextEditingController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => loadActivation());
  }
  @override
  void dispose() { sender.dispose(); super.dispose(); }
  Future<void> loadActivation() async {
    try {
      final result = await Scope.of(context).api.get('/api/subscription/activation');
      if (mounted) setState(() => activationStatus = (result['request'] as Map?)?['status'] as String?);
    } catch (_) { /* Works with older deployed APIs, which have no request status. */ }
  }
  Future<void> requestRenewal() async {
    if (busy) return;
    if (sender.text.trim().isEmpty) {
      message(context, 'اسم صاحب الحوالة مطلوب');
      return;
    }
    setState(() => busy = true);
    try {
      final session = Scope.of(context);
      await session.api.request('POST', '/api/subscription/activation-request', body: {
        'months': selected,
        'senderName': sender.text.trim(),
        'destination': 'bank',
        'receiptImageBase64': receiptBase64,
        'receiptContentType': receiptContentType,
      });
      await loadActivation();
      if (mounted) message(context, 'تم تسجيل طلب الاشتراك، بانتظار موافقة الإدارة');
    } catch (e) { if (mounted) message(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final s = Scope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('الاشتراك والتجديد'),
        automaticallyImplyLeading: !widget.gate,
      ),
      body: Width(
        max: 480,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.workspace_premium_outlined,
                    size: 40,
                    color: s.active ? navy : orange,
                  ),
                  const SizedBox(height: 12),
                  Heading(
                    s.isTrial && s.active
                        ? 'تجربتك المجانية فعّالة'
                        : s.active
                        ? 'اشتراكك فعّال'
                        : s.status?['suspended'] == true
                        ? 'الحساب موقوف'
                        : 'جدّد اشتراكك للمتابعة',
                  ),
                  Text(s.shopName),
                  Text(
                    s.isTrial
                        ? 'متبقي ${s.trialDaysRemaining} يوم من التجربة — تنتهي ${day(s.status?['paidUntil'])}'
                        : 'صالح حتى ${day(s.status?['paidUntil'])}',
                    style: const TextStyle(color: muted),
                  ),
                  if (!s.active)
                    const Text(
                      'بيانات محلك محفوظة. تواصل مع الإدارة لاستعادة الوصول.',
                    ),
                ],
              ),
            ),
            const Heading('اختر مدة الاشتراك'),
            Plans(
              selected: selected,
              select: (v) => setState(() => selected = v),
            ),
            const SizedBox(height: 20),
            _PaymentInstructions(sender: sender, onReceipt: (encoded, mime) {
                      receiptBase64 = encoded;
                      receiptContentType = mime;
                    }),
            const SizedBox(height: 12),
            if (activationStatus == 'Pending')
              const SoftTag('طلب التحويل قيد المراجعة لدى الإدارة')
            else ...[
              BusyButton(label: 'أرسلت التحويل — إرسال طلب التفعيل',
                busy: busy, onPressed: requestRenewal),
              const SizedBox(height: 10),
              Text('لن يتفعّل الاشتراك إلا بعد اعتماد الحوالة من لوحة الإدارة.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, fontSize: 12)),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      await s.reload();
                      if (mounted) setState(() => busy = false);
                    },
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث حالة الاشتراك'),
            ),
            if (widget.gate)
              TextButton(
                onPressed: () async {
                  try {
                    await s.api.logout();
                  } catch (e) {
                    if (context.mounted) message(context, e);
                  }
                },
                child: const Text('تسجيل الخروج من جميع الأجهزة'),
              ),
          ],
        ),
      ),
    );
  }
}

class WorkersScreen extends StatefulWidget {
  const WorkersScreen({super.key});
  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen> {
  List<dynamic> workers = [];
  bool loading = true, saving = false;
  String? error;
  final phone = TextEditingController();
  final password = TextEditingController();
  bool initialized = false;
  @override
  void didChangeDependencies() { super.didChangeDependencies(); if (!initialized) { initialized = true; load(); } }
  @override
  void dispose() { phone.dispose(); password.dispose(); super.dispose(); }
  Future<void> load() async {
    try {
      final result = await Scope.of(context).api.get('/api/workers');
      if (mounted) setState(() { workers = (result['workers'] as List?) ?? []; loading = false; error = null; });
    } catch (e) { if (mounted) setState(() { loading = false; error = '$e'; }); }
  }
  Future<void> add() async {
    if (saving || workers.length >= 2) return;
    final normalized = phoneNumber(phone.text);
    if (normalized == null || password.text.length < 12) {
      message(context, 'أدخل رقم جوال صحيحاً وكلمة مرور من 12 حرفاً على الأقل');
      return;
    }
    setState(() => saving = true);
    try {
      await Scope.of(context).api.request('POST', '/api/workers',
        body: {'phoneNumber': normalized, 'password': password.text});
      phone.clear(); password.clear();
      await load();
      if (mounted) message(context, 'تمت إضافة العامل بنجاح');
    } catch (e) { if (mounted) message(context, '$e'); }
    finally { if (mounted) setState(() => saving = false); }
  }
  Future<void> disable(String id) async {
    try {
      await Scope.of(context).api.request('DELETE', '/api/workers/$id');
      await load();
    } catch (e) { if (mounted) message(context, '$e'); }
  }
  @override
  Widget build(BuildContext context) {
    final s = Scope.of(context);
    return Scaffold(appBar: AppBar(title: const Text('العاملون والصلاحيات'),
        leading: s.workerSetup ? IconButton(
          tooltip: 'بدء استخدام التطبيق',
          onPressed: s.finishWorkerSetup,
          icon: const Icon(Icons.arrow_back)) : null),
      body: Width(child: ListView(padding: const EdgeInsets.all(16), children: [
        BrandCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('فريق المحل', style: appText(19, color: Colors.white, weight: FontWeight.w900)),
          Text(s.shopName, style: appText(12, color: Colors.white70)),
        ])),
        const SizedBox(height: 14),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
        for (final entry in workers)
          Surface(child: Row(children: [
            const Icon(Icons.person_outline, color: navy),
            const SizedBox(width: 12),
            Expanded(child: Text('${entry['phoneNumber']}', style: appText(13))),
            if (entry['enabled'] == true)
              TextButton(onPressed: () => disable('${entry['id']}'),
                child: const Text('تعطيل'))
            else const SoftTag('معطل'),
          ])),
        if (workers.length < 2) Surface(child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('إضافة عامل (${workers.length}/2)',
              style: appText(16, weight: FontWeight.w900)),
            const SizedBox(height: 12),
            TextField(controller: phone, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'رقم جوال العامل')),
            const SizedBox(height: 12),
            TextField(controller: password, obscureText: true,
              decoration: const InputDecoration(labelText: 'كلمة مرور العامل · 12 حرفاً أو أكثر')),
            const SizedBox(height: 12),
            BusyButton(label: 'إضافة عامل', busy: saving, onPressed: add),
          ],
        )),
        const SizedBox(height: 10),
        Text('يسجل العامل الدخول من جهازه برقم الجوال وكلمة مروره، وتُحفظ الحركات في دفتر المحل نفسه.',
          style: appText(11, color: secondaryText)),
      ])),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      owner = TextEditingController(),
      phone = TextEditingController();
  bool ready = false, busy = false;
  String? error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!ready) {
      final s = Scope.of(context);
      name.text = s.shopName;
      owner.text = s.settings?['ownerName'] ?? '';
      phone.text = s.settings?['phone'] ?? '';
      ready = true;
    }
  }

  @override
  void dispose() {
    name.dispose();
    owner.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إعدادات المحل')),
    body: Width(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Heading('معلومات المحل'),
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                field(name, 'اسم المحل', required: true),
                field(owner, 'اسم صاحب المحل'),
                field(
                  phone,
                  'هاتف التواصل',
                  keyboard: TextInputType.phone,
                  max: 30,
                ),
                const Text(
                  'رقم التواصل هنا لا يغيّر رقم تسجيل الدخول.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 20),
                if (error != null) Text(error!),
                BusyButton(
                  label: 'حفظ البيانات',
                  busy: busy,
                  onPressed: () async {
                    if (!form.currentState!.validate()) return;
                    setState(() => busy = true);
                    final s = Scope.of(context);
                    try {
                      final data = await s.api.request(
                        'PUT',
                        '/api/settings',
                        body: {
                          'name': name.text.trim(),
                          'ownerName': owner.text.trim(),
                          'phone': phone.text.trim(),
                        },
                      );
                      s.settings = Map<String, dynamic>.from(data);
                      s.changed();
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (mounted) setState(() => error = '$e');
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Surface(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline, color: navy),
              title: const Text('تغيير كلمة المرور'),
              subtitle: const Text('حماية الوصول إلى حساب المحل'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => open(context, const PasswordScreen()),
            ),
          ),
        ],
      ),
    ),
  );
}

class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});
  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final form = GlobalKey<FormState>();
  final old = TextEditingController(),
      next = TextEditingController(),
      again = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    old.dispose();
    next.dispose();
    again.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تغيير كلمة المرور')),
    body: Width(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in [
                  (old, 'كلمة المرور الحالية'),
                  (next, 'كلمة المرور الجديدة'),
                  (again, 'تأكيد كلمة المرور'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: TextFormField(
                      controller: e.$1,
                      obscureText: true,
                      decoration: InputDecoration(labelText: e.$2),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'هذا الحقل مطلوب';
                        if (e.$1 == next && v.length < 12) {
                          return 'استخدم 12 حرفاً على الأقل';
                        }
                        if (e.$1 == again && v != next.text) {
                          return 'كلمتا المرور غير متطابقتين';
                        }
                        return null;
                      },
                    ),
                  ),
                const Text(
                  'بعد التغيير ستسجّل الدخول مجدداً على جميع الأجهزة.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 18),
                if (error != null) Text(error!),
                BusyButton(
                  label: 'تغيير كلمة المرور',
                  busy: busy,
                  onPressed: () async {
                    if (!form.currentState!.validate()) return;
                    setState(() => busy = true);
                    final s = Scope.of(context);
                    try {
                      await s.api.request(
                        'POST',
                        '/api/auth/change-password',
                        body: {
                          'currentPassword': old.text,
                          'newPassword': next.text,
                        },
                      );
                      await s.api.clear();
                    } catch (e) {
                      if (mounted) setState(() => error = '$e');
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('النسخ الاحتياطي')),
    body: Width(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_done_outlined, color: navy, size: 42),
                const SizedBox(height: 16),
                const Heading('بيانات محلك محفوظة سحابياً'),
                const Text(
                  'الزبائن والموردون والأصناف والحركات مرتبطة بحساب محلك. يمكنك تصدير نسخة إضافية والاحتفاظ بها عند الحاجة.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 18),
                BusyButton(
                  label: 'تصدير نسخة احتياطية',
                  busy: busy,
                  icon: Icons.download_outlined,
                  onPressed: () async {
                    setState(() => busy = true);
                    try {
                      final data = await Scope.of(
                        context,
                      ).api.get('/api/backup/export');
                      if (context.mounted) await Exports.backup(data, context);
                    } catch (e) {
                      if (context.mounted) message(context, e);
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
                ),
              ],
            ),
          ),
          Surface(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sync, color: navy),
              title: const Text('المزامنة والحركات المحفوظة'),
              subtitle: Text(
                '${Scope.of(context).pendingSync} حركة بانتظار المزامنة',
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => open(context, const SyncCenterScreen()),
            ),
          ),
          const Text(
            'الملف يحتوي على بيانات المحل كاملة بصيغة JSON. احفظه في مكان خاص وآمن.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
