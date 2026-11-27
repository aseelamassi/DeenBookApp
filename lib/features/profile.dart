import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:async';
import 'package:image_picker/image_picker.dart';

import '../core/format.dart';
import '../core/collection_accounts.dart';
import '../core/session.dart';
import '../services/export.dart';
import '../services/subscription_contact.dart';
import '../ui/theme.dart';
import '../ui/design.dart';
import '../ui/password_strength.dart';
import 'sync_center.dart';
import '../ui/widgets.dart';

// API values agreed with the existing Registration and Subscription endpoints.
const _paymentDestinationLabels = <String, String>{
  'bank': 'بنك فلسطين',
  'palpay': 'محفظة PalPay',
  'jawwal': 'جوال بي',
};

String _paymentDestinationLabel(String destination) =>
    _paymentDestinationLabels[destination] ?? 'بنك فلسطين';

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
  String paymentDestination = 'bank';
  bool trial = true, passwordHidden = true, busy = false;
  // Becomes true only after the server confirms initial paid registration.
  // Editing the transfer must NEVER call POST /api/registration again.
  bool paidRegistrationCreated = false;
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
      final result = paidRegistrationCreated
          ? await s.api.updatePendingRegistration({
              'phoneNumber': phoneNumber(phone.text),
              'password': password.text,
              'months': selected,
              'senderName': sender.text.trim(),
              'destination': paymentDestination,
              'receiptImageBase64': receiptBase64,
              'receiptContentType': receiptContentType,
            })
          : await s.api.registerShop({
              'shopName': name.text.trim(),
              'ownerName': owner.text.trim(),
              'phoneNumber': phoneNumber(phone.text),
              'password': password.text,
              'freeTrial': trial,
              'months': selected,
              'senderName': trial ? null : sender.text.trim(),
              'destination': paymentDestination,
              'receiptImageBase64': receiptBase64,
              'receiptContentType': receiptContentType,
            });
      if (!mounted) return;
      if (!trial && result['state'] == 'Pending') {
        paidRegistrationCreated = true;
      }
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
            destination: paymentDestination,
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
                          'افتح دفتر محلك الإلكتروني في دقيقة',
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
                        field(
                          phone,
                          'رقم الجوال',
                          keyboard: TextInputType.phone,
                          validator: (v) => phoneNumber(v ?? '') == null
                              ? 'أدخل رقم جوال صحيحاً'
                              : null,
                        ),
                        if (!widget.reset)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  key: const Key('registration-password'),
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
                                PasswordStrengthIndicator(controller: password),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                if (!widget.reset && step == 1) ...[
                  InkWell(
                    onTap: paidRegistrationCreated
                        ? () => message(context,
                            'تم إنشاء طلب اشتراك مدفوع لهذا المحل؛ يمكنك تعديل بيانات التحويل أو مدة الاشتراك فقط.')
                        : () => setState(() => trial = true),
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
                    _PaymentInstructions(
                      sender: sender,
                      destination: paymentDestination,
                      onDestinationChanged: (value) => setState(() => paymentDestination = value),
                      onReceipt: (encoded, mime) {
                        receiptBase64 = encoded;
                        receiptContentType = mime;
                      },
                    ),
                    const SizedBox(height: 12),
                    Text('بعد تسجيل الطلب على الخادم يبقى قيد المراجعة حتى يؤكد الأدمن وصول الحوالة.', style: appText(11, color: secondaryText)),
                  ],
                ],
                if (!widget.reset && step == 2 && paidRegistrationCreated) ...[
                  const SizedBox(height: 12),
                  Text(
                    'أنت الآن تعدّل طلب التفعيل الحالي، ولن يتم تسجيل محل أو رقم جوال جديد.',
                    style: appText(12, color: secondaryText),
                  ),
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
                      ? (widget.reset
                          ? 'طلب استعادة الحساب'
                          : trial
                              ? 'طلب بدء تجربة مجانية'
                              : paidRegistrationCreated
                                  ? 'حفظ تعديلات طلب التفعيل'
                                  : 'أرسلت التحويل — إرسال طلب التفعيل')
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

/// Payment details from the supplied merchant screenshot; destination codes
/// match the existing Backend API values. The payee stays visible on selection.
class _PaymentInstructions extends StatefulWidget {
  const _PaymentInstructions({
    required this.sender,
    required this.destination,
    required this.onDestinationChanged,
    required this.onReceipt,
  });
  final TextEditingController sender;
  final String destination;
  final ValueChanged<String> onDestinationChanged;
  final void Function(String?, String?) onReceipt;

  @override
  State<_PaymentInstructions> createState() => _PaymentInstructionsState();
}

class _PaymentInstructionsState extends State<_PaymentInstructions> {
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
    } catch (e) {
      if (mounted) message(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('تحويل رسوم الاشتراك وتفعيل المحل',
            style: appText(17, weight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('أولاً: اختر وجهة التحويل',
            style: appText(13, weight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final method in _paymentDestinationLabels.entries)
              ChoiceChip(
                label: Text(method.value),
                selected: widget.destination == method.key,
                onSelected: (_) => widget.onDestinationChanged(method.key),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: lavender,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: lineColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('بيانات صاحب التطبيق لاستلام رسوم الاشتراك',
                  style: appText(13, weight: FontWeight.w900)),
              const SizedBox(height: 6),
              _copyLine(context, 'اسم صاحب الحساب المستلم', 'لؤي محمد أبو زعنونة'),
              _copyLine(context, 'رقم الجوال (بنك فلسطين، PalPay، جوال بي)', '0594301646'),
              _copyLine(context, 'آيبان بنك فلسطين (للتحويل البنكي فقط)',
                  'PS92PALS045310978160993000000'),
              const SizedBox(height: 6),
              Text(
                widget.destination == 'bank'
                    ? 'استخدمي بيانات بنك فلسطين للتحويل البنكي.'
                    : 'للتحويل عبر ${_paymentDestinationLabel(widget.destination)} استخدمي رقم الجوال الظاهر أعلاه، وتحققي من اسم المستلم في خدمة التحويل قبل الإرسال.',
                style: appText(11, color: secondaryText),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text('ثانياً: اسم صاحب الحوالة',
            style: appText(12, weight: FontWeight.w800)),
        const SizedBox(height: 6),
        TextField(
          controller: widget.sender,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'اسم صاحب الحوالة',
            hintText: 'اكتب الاسم كما يظهر في التحويل',
          ),
        ),
        const SizedBox(height: 8),
        Text('ستُرسل وجهة التحويل واسم صاحبه إلى لوحة الإدارة للتحقق من الحوالة يدوياً.',
            style: appText(11, color: secondaryText)),
        const SizedBox(height: 12),
        Text('ثالثاً: صورة إشعار التحويل (اختياري)',
            style: appText(12, weight: FontWeight.w800)),
        OutlinedButton.icon(
          onPressed: chooseReceipt,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(chosenImage == null
              ? 'إرفاق صورة إشعار التحويل' : 'تم اختيار الصورة · تغيير'),
        ),
        if (chosenImage != null)
          Text(chosenImage!, style: appText(11, color: secondaryText)),
      ],
    ),
  );

  Widget _copyLine(BuildContext context, String title, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: appText(11, color: secondaryText)),
                    SelectableText(
                      value,
                      textDirection: value.startsWith('PS') || value.startsWith('05')
                          ? TextDirection.ltr : TextDirection.rtl,
                      style: appText(12, weight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'نسخ $title',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: value));
                  if (context.mounted) message(context, 'تم النسخ');
                },
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
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
  const _PendingActivationPreview({required this.shop, required this.owner,
    required this.months, required this.sender, required this.destination});
  final String shop, owner, sender, destination;
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
        Text('وجهة التحويل: ${_paymentDestinationLabel(destination)}'),
        if (sender.isNotEmpty) Text('اسم صاحب الحوالة: $sender'),
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
  String paymentDestination = 'bank';
  bool busy = false;
  bool checkingActivation = true;
  String? activationStatus, activationError, receiptBase64, receiptContentType;
  Map<String, dynamic>? activationRequest;
  final sender = TextEditingController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => loadActivation());
  }
  @override
  void dispose() { sender.dispose(); super.dispose(); }
  Future<void> loadActivation() async {
    if (!mounted) return;
    setState(() {
      checkingActivation = true;
      activationError = null;
    });
    try {
      final result = await Scope.of(context).api.get('/api/subscription/activation');
      if (!mounted) return;
      final raw = result['request'];
      final request = raw is Map<String, dynamic>
          ? raw
          : raw is Map
              ? Map<String, dynamic>.from(raw)
              : null;
      setState(() {
        activationRequest = request;
        activationStatus = request?['status'] as String?;
        checkingActivation = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        activationError = '$e';
        checkingActivation = false;
      });
    }
  }

  Future<void> refreshActivation() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await Scope.of(context).reload();
      if (!mounted) return;
      await loadActivation();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> signOut() async {
    try {
      await Scope.of(context).api.logout();
    } catch (e) {
      if (mounted) message(context, '$e');
    }
  }

  Widget pendingReview(Session s) => Width(
    max: 480,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.hourglass_empty_rounded, color: orange, size: 54),
        const SizedBox(height: 16),
        Text('طلب اشتراك قيد المراجعة',
            textAlign: TextAlign.center,
            style: appText(23, weight: FontWeight.w900)),
        const SizedBox(height: 10),
        Text('تم استلام طلب تفعيل المحل. بانتظار تأكيد الحوالة وموافقة الإدارة، ولا تحتاج إلى اختيار باقة أو إرسال طلب جديد.',
            textAlign: TextAlign.center,
            style: appText(12, color: secondaryText)),
        const SizedBox(height: 18),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('المحل: ${s.shopName}', style: appText(13, weight: FontWeight.w800)),
              if (activationRequest?['months'] is num) ...[
                const SizedBox(height: 8),
                Text('الخطة: ${(activationRequest!['months'] as num).toInt() == 1 ? 'شهر واحد · 60 ₪' : '3 أشهر · 150 ₪'}'),
              ],
              if ('${activationRequest?['senderName'] ?? ''}'.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('اسم صاحب الحوالة: ${activationRequest!['senderName']}'),
              ],
              if ('${activationRequest?['destination'] ?? ''}'.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('وجهة التحويل: ${_paymentDestinationLabel(activationRequest!['destination'].toString())}'),
              ],
              const SizedBox(height: 12),
              const SoftTag('بانتظار موافقة الإدارة'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        BusyButton(
          label: 'تحديث حالة الطلب',
          busy: busy,
          onPressed: refreshActivation,
        ),
        const SizedBox(height: 10),
        TextButton(onPressed: signOut, child: const Text('تسجيل الخروج')),
      ],
    ),
  );

  Widget activationLoadFailure() => Width(
    max: 480,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.error_outline_rounded, color: orange, size: 48),
        const SizedBox(height: 12),
        Text('تعذّر التحقق من حالة طلب الاشتراك',
            textAlign: TextAlign.center,
            style: appText(20, weight: FontWeight.w900)),
        const SizedBox(height: 10),
        Text('لن نطلب منك اختيار باقة جديدة قبل معرفة حالة طلب التفعيل الموجود.',
            textAlign: TextAlign.center,
            style: appText(12, color: secondaryText)),
        const SizedBox(height: 12),
        if (activationError != null)
          Text(activationError!, textAlign: TextAlign.center,
              style: appText(11, color: secondaryText)),
        const SizedBox(height: 16),
        BusyButton(
          label: 'إعادة التحقق',
          busy: busy,
          onPressed: refreshActivation,
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: signOut, child: const Text('تسجيل الخروج')),
      ],
    ),
  );
  Future<void> requestRenewal() async {
    if (busy) return;
    if (sender.text.trim().isEmpty) {
      message(context, 'اسم صاحب الحوالة مطلوب');
      return;
    }
    setState(() => busy = true);
    try {
      final session = Scope.of(context);
      final submittedMonths = selected;
      final submittedSender = sender.text.trim();
      final submittedDestination = paymentDestination;
      final result = await session.api.request(
        'POST',
        '/api/subscription/activation-request',
        body: {
          'months': submittedMonths,
          'senderName': submittedSender,
          'destination': submittedDestination,
          'receiptImageBase64': receiptBase64,
          'receiptContentType': receiptContentType,
        },
      );
      if (!mounted) return;
      // The successful POST is the authoritative confirmation that the
      // renewal request was saved. Do not wait for a second GET before
      // displaying the full pending-review page: it may be stale or fail.
      if (result is! Map ||
          '${result['status']}'.toLowerCase() != 'pending') {
        message(context, 'لم يؤكد الخادم أن طلب الاشتراك قيد المراجعة. تحقّق من حالة الطلب قبل إعادة الإرسال.');
        return;
      }
      setState(() {
        activationRequest = {
          if (result is Map && result['id'] != null) 'id': result['id'],
          'status': 'Pending',
          'months': submittedMonths,
          'senderName': submittedSender,
          'destination': submittedDestination,
        };
        activationStatus = 'Pending';
        activationError = null;
        checkingActivation = false;
      });
    } catch (e) { if (mounted) message(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final s = Scope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(activationStatus == 'Pending'
            ? 'متابعة طلب التفعيل' : 'الاشتراك والتجديد'),
        automaticallyImplyLeading: !widget.gate,
      ),
      body: checkingActivation
          ? const Center(child: CircularProgressIndicator())
          : activationStatus == 'Pending'
          ? pendingReview(s)
          : activationError != null
          ? activationLoadFailure()
          : Width(
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
                  if (!s.active) ...[
                    const Text('بيانات المحل والزبائن والحركات محفوظة، ويمكنك تجديد الاشتراك دون إنشاء حساب جديد.'),
                    const SizedBox(height: 12),
                    Text('خطوات التجديد', style: appText(12, weight: FontWeight.w900)),
                    const Text(
                      '1. اختر مدة الاشتراك المناسبة.\n'
                      '2. حوّل الرسوم وأدخل معلومات الحوالة.\n'
                      '3. أرسل الطلب، ثم تابع مراجعته حتى موافقة الإدارة.',
                    ),
                  ],
                ],
              ),
            ),
            const Heading('اختر مدة الاشتراك'),
            Plans(
              selected: selected,
              select: (v) => setState(() => selected = v),
            ),
            const SizedBox(height: 20),
            _PaymentInstructions(
              sender: sender,
              destination: paymentDestination,
              onDestinationChanged: (value) => setState(() => paymentDestination = value),
              onReceipt: (encoded, mime) {
                receiptBase64 = encoded;
                receiptContentType = mime;
              },
            ),
            const SizedBox(height: 12),
            BusyButton(label: 'أرسلت التحويل — إرسال طلب التفعيل',
              busy: busy, onPressed: requestRenewal),
            const SizedBox(height: 10),
            Text('لن يتفعّل الاشتراك إلا بعد اعتماد الحوالة من لوحة الإدارة.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      await refreshActivation();
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

String workerDisplayName(Map worker) {
  final name = '${worker['name'] ?? ''}'.trim();
  if (name.isNotEmpty) return name;
  return '${worker['phoneNumber'] ?? 'عامل المحل'}';
}

class WorkersScreen extends StatefulWidget {
  const WorkersScreen({super.key});
  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen> {
  List<dynamic> workers = [];
  List<dynamic> pendingDeletes = [];
  Session? _session;
  int _seenRevision = -1;
  int _loadGeneration = 0;
  Timer? _setupSyncTimer;
  bool loading = true, saving = false;
  String? error;
  final name = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();
  bool initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = Scope.of(context);
    if (_session != session) {
      _session?.removeListener(_onSessionChanged);
      _session = session;
      _seenRevision = session.revision;
      session.addListener(_onSessionChanged);
    }
    if (!initialized) {
      initialized = true;
      load();
      // During initial setup there is no AppShell timer yet.
      if (session.workerSetup) {
        _setupSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
          if (mounted && (session.pendingSync > 0 || session.isOffline)) {
            unawaited(session.synchronize());
          }
        });
      }
    }
  }
  void _onSessionChanged() {
    if (!mounted || _session == null || _seenRevision == _session!.revision) return;
    _seenRevision = _session!.revision;
    if (!saving) load();
  }
  @override
  void dispose() {
    _session?.removeListener(_onSessionChanged);
    _setupSyncTimer?.cancel();
    name.dispose(); phone.dispose(); password.dispose(); super.dispose();
  }
  Future<void> load() async {
    final generation = ++_loadGeneration;
    final api = Scope.of(context).api;
    try {
      final result = await api.get('/api/workers');
      if (mounted && generation == _loadGeneration) setState(() {
        // Disabled accounts are treated as deleted in the owner interface and
        // do not occupy one of the two active worker slots.
        workers = ((result['workers'] as List?) ?? [])
            .where((entry) => entry is Map && entry['enabled'] == true)
            .toList();
        pendingDeletes = (result['pendingWorkerDeletes'] as List?) ?? [];
        loading = false;
        error = null;
      });
    } catch (e) {
      final pending = await api.pendingWorkerDeletes();
      if (mounted && generation == _loadGeneration) setState(() {
        pendingDeletes = pending;
        final ids = pending.map((entry) => '${entry['workerId']}').toSet();
        workers.removeWhere((entry) => ids.contains('${entry['id']}'));
        loading = false; error = '$e';
      });
    }
  }
  Future<void> add() async {
    if (saving || workers.length >= 2) return;
    final session = Scope.of(context);
    if (session.isOffline) {
      message(context, 'إضافة عامل جديد تحتاج إلى اتصال بالإنترنت.');
      return;
    }
    final normalized = phoneNumber(phone.text);
    if (name.text.trim().isEmpty || name.text.trim().length > 160 ||
        normalized == null || password.text.length < 12) {
      message(context, 'أدخل اسم العامل ورقم جوال صحيحاً وكلمة مرور من 12 حرفاً على الأقل');
      return;
    }
    setState(() => saving = true);
    try {
      if ((await session.api.pendingWorkerDeletes()).isNotEmpty) {
        await session.synchronize();
        if (!mounted) return;
        await load();
        if (!mounted) return;
        if ((await session.api.pendingWorkerDeletes()).isNotEmpty) {
          if (mounted) message(context, 'زامن حذف العامل أولاً قبل إضافة عامل جديد.');
          return;
        }
      }
      if (!mounted || workers.length >= 2) return;
      await session.api.request('POST', '/api/workers', body: {
        'name': name.text.trim(), 'phoneNumber': normalized, 'password': password.text,
      });
      if (!mounted) return;
      name.clear(); phone.clear(); password.clear();
      await load();
      if (mounted) message(context, 'تمت إضافة العامل بنجاح');
    } catch (e) { if (mounted) message(context, '$e'); }
    finally { if (mounted) setState(() => saving = false); }
  }
  Future<void> renameWorker(Map entry) async {
    if (saving) return;
    final id = '${entry['id']}';
    final initialName = '${entry['name'] ?? ''}';
    var draftName = initialName;
    try {
      final updatedName = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تعديل اسم العامل'),
          content: TextFormField(
            initialValue: initialName,
            onChanged: (value) => draftName = value,
            maxLength: 160,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'اسم العامل'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء')),
            TextButton(onPressed: () {
              final value = draftName.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            }, child: const Text('حفظ الاسم')),
          ],
        ),
      );
      if (updatedName == null || !mounted) return;
      setState(() => saving = true);
      await Scope.of(context).api.request('PUT', '/api/workers/$id/name',
          body: {'name': updatedName});
      await load();
      if (mounted) message(context, 'تم تحديث اسم العامل');
    } catch (e) {
      if (mounted) message(context, '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
  Future<void> deleteWorker(Map entry) async {
    if (saving) return;
    final id = '${entry['id']}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف العامل'),
        content: Text(
          'هل تريد حذف حساب ${workerDisplayName(entry)}؟ إذا لم يتوفر اتصال، سيُحفظ الطلب محلياً ويُنفّذ على الخادم عند المزامنة. تبقى الحركات السابقة محفوظة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف العامل'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => saving = true);
    try {
      final session = Scope.of(context);
      final result = await session.api.deleteWorker(id, workerDisplayName(entry));
      final pending = await session.api.pendingWorkerDeletes();
      _loadGeneration++;
      if (mounted) setState(() {
        workers.removeWhere((w) => '${w['id']}' == id);
        pendingDeletes = pending;
      });
      await session.updatePending();
      if (!mounted) return;
      await load();
      if (mounted) message(context, result['queued'] == true
          ? 'تم حفظ طلب حذف العامل محلياً، وسيُنفّذ عند المزامنة.'
          : 'تم حذف العامل، ويمكنك إضافة عامل جديد الآن');
    } catch (e) { if (mounted) message(context, '$e'); }
    finally { if (mounted) setState(() => saving = false); }
  }
  @override
  Widget build(BuildContext context) {
    final s = Scope.of(context);
    return Scaffold(appBar: AppBar(title: const Text('العاملون والصلاحيات'),
        leading: s.workerSetup ? IconButton(
          tooltip: 'بدء استخدام التطبيق',
          onPressed: s.finishWorkerSetup,
          icon: const BackButtonIcon()) : null),
      body: Width(child: ListView(padding: const EdgeInsets.all(16), children: [
        BrandCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('فريق المحل', style: appText(19, color: Colors.white, weight: FontWeight.w900)),
          Text(s.shopName, style: appText(12, color: Colors.white70)),
        ])),
        const SizedBox(height: 14),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
        if (pendingDeletes.isNotEmpty) Surface(child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${pendingDeletes.length} طلب حذف عامل بانتظار تأكيد الخادم',
                style: const TextStyle(color: orange)),
            for (final entry in pendingDeletes)
              Text('${entry['workerName'] ?? 'عامل'}${entry['lastError'] == null ? '' : ' — ${entry['lastError']}'}'),
            OutlinedButton.icon(
              onPressed: saving || s.syncing ? null : () async {
                await s.synchronize();
                if (mounted) await load();
              },
              icon: const Icon(Icons.sync),
              label: const Text('مزامنة الآن'),
            ),
          ],
        )),
        for (final entry in workers)
          Surface(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Icon(Icons.person_outline, color: navy),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(workerDisplayName(entry as Map),
                        style: appText(13, weight: FontWeight.w800)),
                    Text('${entry['phoneNumber']}',
                        style: appText(11, color: secondaryText)),
                  ],
                )),
              ]),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: saving ? null : () => renameWorker(
                        Map<String, dynamic>.from(entry as Map)),
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const Text('تعديل الاسم'),
                  ),
                  TextButton.icon(
                    onPressed: saving ? null : () => deleteWorker(
                        Map<String, dynamic>.from(entry as Map)),
                    icon: const Icon(Icons.delete_outline, size: 17),
                    label: const Text('حذف'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              ),
            ],
          )),
        if (workers.length < 2) Surface(child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('إضافة عامل (${workers.length}/2)',
              style: appText(16, weight: FontWeight.w900)),
            const SizedBox(height: 12),
            TextField(controller: name, maxLength: 160,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'اسم العامل')),
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
        Text('يسجل صاحب المحل وكل عامل الدخول من جهازه في أي وقت. تُحفظ الحركات في دفتر المحل نفسه مع تسجيل اسم المستخدم الذي نفّذ كل حركة.',
          style: appText(11, color: secondaryText)),
      ])),
    );
  }
}

/// The worker sees their own authenticated identity, not the shop owner's
/// editable settings or any subscription/payment screens.
class WorkerProfileScreen extends StatelessWidget {
  const WorkerProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Scope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ملفي الشخصي')),
      body: Width(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Heading('بيانات العامل'),
            Surface(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الاسم', style: appText(12, color: secondaryText)),
                Text(session.currentUserName,
                    style: appText(18, weight: FontWeight.w800)),
                const SizedBox(height: 14),
                Text('رقم الجوال', style: appText(12, color: secondaryText)),
                SelectableText(session.currentUserPhone.isEmpty
                    ? 'غير متوفر' : session.currentUserPhone,
                    textDirection: TextDirection.ltr,
                    style: appText(15, weight: FontWeight.w700)),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () => open(context, const PasswordScreen()),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('تغيير كلمة المرور'),
                ),
              ],
            )),
          ],
        ),
      ),
    );
  }
}

/// Workers may not initiate renewals; only the owner can submit payment details.
class WorkerSubscriptionLockedScreen extends StatelessWidget {
  const WorkerSubscriptionLockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Scope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('حالة اشتراك المحل')),
      body: Width(child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Surface(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 36, color: orange),
              SizedBox(height: 12),
              Heading('اشتراك المحل بحاجة إلى تجديد'),
              Text('يرجى التواصل مع صاحب المحل لتجديد الاشتراك. لا يمكن للعامل اختيار باقة أو إرسال حوالة.'),
            ],
          )),
          const SizedBox(height: 12),
          BusyButton(label: 'تحديث حالة المحل', onPressed: session.reload),
          TextButton(onPressed: session.api.clear,
              child: const Text('تسجيل الخروج')),
        ],
      )),
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
  final collectionAccounts = <ShopCollectionAccount>[];

  Future<void> editCollectionAccount([int? index]) async {
    if (busy || (index == null && collectionAccounts.length >= 20)) return;
    final existing = index == null ? null : collectionAccounts[index];
    final holder = TextEditingController(text: existing?.accountHolder ?? '');
    final number = TextEditingController(text: existing?.accountNumber ?? '');
    final bankName = TextEditingController(text: existing?.bankName ?? '');
    final key = GlobalKey<FormState>();
    var method = existing?.method ?? 'Bank';
    try {
      final result = await showDialog<ShopCollectionAccount>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, updateDialog) => AlertDialog(
            title: Text(index == null ? 'إضافة وسيلة تحصيل' : 'تعديل وسيلة التحصيل'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Form(
                  key: key,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: method,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'وجهة التحويل'),
                        items: collectionMethodLabels.entries.map((entry) =>
                          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                        ).toList(),
                        onChanged: (value) {
                          if (value != null) updateDialog(() => method = value);
                        },
                      ),
                      if (method == 'Bank') ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: bankName,
                          maxLength: 100,
                          decoration: const InputDecoration(labelText: 'اسم البنك'),
                          validator: (value) => (value ?? '').trim().isEmpty
                            ? 'أدخل اسم البنك' : null,
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: holder,
                        maxLength: 160,
                        decoration: const InputDecoration(labelText: 'اسم صاحب الحساب'),
                        validator: (value) => (value ?? '').trim().isEmpty
                          ? 'أدخل اسم صاحب الحساب' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: number,
                        maxLength: 80,
                        textDirection: TextDirection.ltr,
                        keyboardType: TextInputType.text,
                        decoration: const InputDecoration(labelText: 'رقم التحويل / المحفظة / IBAN'),
                        validator: (value) => (value ?? '').trim().isEmpty
                          ? 'أدخل رقم الحساب أو المحفظة' : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
              FilledButton(
                onPressed: () {
                  if (!key.currentState!.validate()) return;
                  Navigator.pop(dialogContext, ShopCollectionAccount(
                    method: method,
                    accountHolder: holder.text.trim(),
                    accountNumber: number.text.trim(),
                    bankName: method == 'Bank' ? bankName.text.trim() : '',
                  ));
                },
                child: const Text('اعتماد'),
              ),
            ],
          ),
        ),
      );
      if (result == null || !mounted) return;
      setState(() {
        if (index == null) {
          collectionAccounts.add(result);
        } else {
          collectionAccounts[index] = result;
        }
        error = null;
      });
    } finally {
      holder.dispose();
      number.dispose();
      bankName.dispose();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!ready) {
      final s = Scope.of(context);
      name.text = s.shopName;
      owner.text = s.settings?['ownerName'] ?? '';
      phone.text = s.settings?['phone'] ?? '';
      collectionAccounts.addAll(collectionAccountsFromSettings(s.settings));
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
                const SizedBox(height: 18),
                const Heading('معلومات التحويل والتحصيل'),
                const Text(
                  'أضف أكثر من حساب بنكي أو محفظة. ستظهر المعلومات المحفوظة في تقارير المحل وملخصات الزبائن وكشف حسابهم.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                for (var index = 0; index < collectionAccounts.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Surface(
                      child: Row(
                        children: [
                          const Icon(Icons.account_balance_wallet_outlined, color: navy),
                          const SizedBox(width: 8),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(collectionAccounts[index].destination,
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(collectionAccounts[index].accountHolder),
                              SelectableText(collectionAccounts[index].accountNumber,
                                textDirection: TextDirection.ltr),
                            ],
                          )),
                          IconButton(
                            tooltip: 'تعديل وسيلة التحصيل',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: busy ? null : () => editCollectionAccount(index),
                          ),
                          IconButton(
                            tooltip: 'حذف وسيلة التحصيل',
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: busy ? null : () => setState(() => collectionAccounts.removeAt(index)),
                          ),
                        ],
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: busy || collectionAccounts.length >= 20
                    ? null : () => editCollectionAccount(),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة حساب أو محفظة أخرى'),
                ),
                const Text(
                  'يُعتمد الإضافة أو التعديل أو الحذف عند الضغط على «حفظ البيانات» أدناه.',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
                const SizedBox(height: 20),
                if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
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
                          'collectionAccounts': collectionAccounts.map((e) => e.toJson()).toList(),
                        },
                      );
                      if (data is! Map || !data.containsKey('collectionAccounts')) {
                        throw StateError('الخادم لم يدعم حفظ وسائل التحصيل بعد. حدّث Backend أولًا.');
                      }
                      s.settings = Map<String, dynamic>.from(data);
                      if (context.mounted) Navigator.pop(context);
                      // Let the settings route finish closing before notifying
                      // the app shell, which also rebuilds shop-name labels.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        s.changed();
                      });
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

/// Translate the known invalid-current-password response in this screen only.
/// Other server errors remain unchanged for troubleshooting.
String passwordChangeErrorText(Object error) {
  final raw = error.toString().trim();
  final normalized = raw.toLowerCase().replaceAll(RegExp(r'[\s.!؟]+$'), '');
  if (normalized == 'incorrect password' ||
      normalized == 'current password is incorrect') {
    return 'كلمة المرور الحالية غير صحيحة. تأكد منها وحاول مرة أخرى.';
  }
  return raw;
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
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      error!,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Color(0xFFB42318),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                BusyButton(
                  label: 'تغيير كلمة المرور',
                  busy: busy,
                  onPressed: () async {
                    if (!form.currentState!.validate()) return;
                    setState(() {
                      busy = true;
                      error = null;
                    });
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
                      if (mounted) {
                        setState(() => error = passwordChangeErrorText(e));
                      }
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
  bool exporting = false;
  @override
  Widget build(BuildContext context) {
    final session = Scope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('الحفظ واستعادة البيانات')),
      body: Width(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.cloud_done_outlined, color: navy, size: 42),
                  SizedBox(height: 16),
                  Heading('بيانات المحل محفوظة على حسابك'),
                  SizedBox(height: 8),
                  Text(
                    'الزبائن والموردون والأصناف والحركات التي تمت مزامنتها '
                    'محفوظة على السيرفر، وليست مرتبطة بهذا الهاتف وحده.',
                    style: TextStyle(color: muted),
                  ),
                  SizedBox(height: 18),
                  Heading('كيف تستعيد بياناتك على جهاز آخر؟'),
                  SizedBox(height: 10),
                  Text('1. نزّل تطبيق دفتر دين على الجهاز الآخر.'),
                  SizedBox(height: 6),
                  Text('2. سجّل الدخول برقم جوالك وكلمة مرور حسابك نفسه.'),
                  SizedBox(height: 6),
                  Text('3. مع اتصال الإنترنت واشتراك المحل الفعّال، '
                      'ستظهر بيانات المحل التي وصلت إلى السيرفر.'),
                ],
              ),
            ),
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        session.pendingSync > 0
                            ? Icons.warning_amber_rounded
                            : Icons.cloud_done_outlined,
                        color: session.pendingSync > 0 ? orange : navy,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          session.pendingSync > 0
                              ? '${session.pendingSync} عملية لم تُزامَن بعد'
                              : 'لا توجد حركات معلّقة للمزامنة',
                          style: appText(14, weight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'مهم: الحركات التي لم تُزامَن تبقى على الجهاز الحالي '
                    'ولا تنتقل تلقائيًا إلى هاتف آخر. شغّل الإنترنت وأكمل '
                    'المزامنة قبل تبديل الجهاز أو تسجيل الخروج.',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.sync, color: navy),
                    title: const Text('فحص الحركات ومزامنتها'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => open(context, const SyncCenterScreen()),
                  ),
                ],
              ),
            ),
            if (session.isOwner)
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Heading('نسخة أرشيفية اختيارية (JSON)'),
                    const SizedBox(height: 10),
                    const Text(
                      'يمكنك تنزيل ملف أرشيفي لبيانات الدفتر المتاحة في '
                      'التصدير. هذا الملف ليس وسيلة لاستعادة الحساب؛ '
                      'التطبيق لا يدعم استيراد JSON، ولا يغني التصدير '
                      'عن مزامنة الحركات مع السيرفر.',
                      style: TextStyle(color: muted),
                    ),
                    const SizedBox(height: 14),
                    BusyButton(
                      label: 'تنزيل ملف JSON أرشيفي',
                      busy: exporting,
                      icon: Icons.download_outlined,
                      onPressed: () async {
                        setState(() => exporting = true);
                        try {
                          final data = await session.api.get('/api/backup/export');
                          if (context.mounted) await Exports.backup(data, context);
                        } catch (e) {
                          if (context.mounted) message(context, e);
                        } finally {
                          if (mounted) setState(() => exporting = false);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'يحوي الملف معلومات عملاء وحركات حساسة؛ احتفظ به '
                      'في مكان آمن ولا تشاركه مع الآخرين.',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
