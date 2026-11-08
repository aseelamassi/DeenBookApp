import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  bool trial = true, passwordHidden = true;
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
                              validator: (v) => (v?.length ?? 0) < 8
                                  ? 'كلمة المرور يجب أن تكون 8 أحرف على الأقل'
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
                    const SizedBox(height: 12),
                    Text('بدء الفترة المجانية وتواريخها الفعلية يتطلبان إنشاء الحساب من الخادم؛ لا يبدأ احتسابها بمجرد عرض هذه الصفحة.', style: appText(11, color: secondaryText)),
                  ] else ...[
                    _PaymentInstructions(sender: sender),
                    const SizedBox(height: 12),
                    Text('بعد التحويل وإرسال الطلب سيظل الاشتراك قيد المراجعة لحين تأكيد الإدارة. هذه الشاشة لا تثبت وصول التحويل.', style: appText(11, color: secondaryText)),
                  ],
                ],
                const SizedBox(height: 24),
                BusyButton(
                  label: widget.reset || step == 2
                      ? (widget.reset ? 'طلب استعادة الحساب' : trial ? 'طلب بدء تجربة مجانية' : 'أرسلت التحويل — إرسال طلب التفعيل')
                      : 'متابعة ←',
                  onPressed: () async {
                    if ((widget.reset || step == 0) &&
                        !form.currentState!.validate()) {
                      return;
                    }
                    if (widget.reset || step == 2) {
                      await contact(context, request);
                      if (mounted && !widget.reset && !trial) {
                        Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => _PendingActivationPreview(shop: name.text.trim(), owner: owner.text.trim(), months: selected, sender: sender.text.trim()),
                        ));
                      }
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
                      : 'كلمة المرور لا تُرسل للإدارة أو عبر واتساب. تفعيل الحساب وربط العاملين يحتاجان دعم الخادم.',
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
  const _PaymentInstructions({required this.sender});
  final TextEditingController sender;
  @override
  State<_PaymentInstructions> createState() => _PaymentInstructionsState();
}

class _PaymentInstructionsState extends State<_PaymentInstructions> {
  int destination = 0;
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
          ChoiceChip(label: Text(label), selected: destination == i, onSelected: (_) => setState(() => destination = i)),
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
      Text('رفع الصورة وإرسالها للإدارة يتطلب واجهة Backend للملفات. لا يتم رفع أي مستند من هذه النسخة.', style: appText(11, color: secondaryText)),
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

class _TrialInformation extends StatelessWidget {
  const _TrialInformation();
  @override
  Widget build(BuildContext context) => Surface(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('تجربة مجانية لمدة 14 يوماً', style: appText(18, weight: FontWeight.w900, color: green)),
      const Text('سيظهر تاريخ البداية والانتهاء فور تأكيد إنشاء الحساب من الخادم.'),
      const SizedBox(height: 10),
      OutlinedButton.icon(onPressed: () => message(context, 'إضافة عاملين اثنين تتطلب تفعيل الحساب وربط العاملين من الخادم.'), icon: const Icon(Icons.people_outline), label: const Text('إضافة عاملين')),
      OutlinedButton.icon(onPressed: () => message(context, 'بعد إنشاء الحساب وتفعيل التجربة من الخادم، سجّل الدخول برقم الجوال وكلمة المرور لبدء الاستخدام.'), icon: const Icon(Icons.login), label: const Text('البدء باستخدام التطبيق')),
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
      Text('هذه معاينة لحالة قيد التفعيل. لم يتم التأكد من إرسال الطلب أو وصول الحوالة إلى الخادم بعد. تظهر الحالة الرسمية بعد ربط واجهة التسجيل بالـ Backend.', textAlign: TextAlign.center, style: appText(12, color: secondaryText)),
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
            BusyButton(
              label: hasSupportContact
                  ? 'متابعة التجديد عبر واتساب'
                  : 'عرض طلب التجديد',
              onPressed: () => contact(
                context,
                subscriptionRequestText(
                  shopName: s.shopName,
                  months: selected,
                  phone: s.settings?['phone'] as String?,
                  renewal: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              hasSupportContact
                  ? 'أرسل الرسالة من واتساب لإكمال الطلب. تأكيد الدفع والتفعيل يتمان من الإدارة.'
                  : 'لم يُرسل أي طلب. التواصل من التطبيق غير متاح حالياً؛ يمكنك عرض التفاصيل ونسخها.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12),
            ),
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

class WorkersScreen extends StatelessWidget {
  const WorkersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = Scope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('العاملون والصلاحيات')),
      body: Width(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            BrandCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'فريق المحل',
                    style: appText(
                      18,
                      color: Colors.white,
                      weight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'حسابات العاملين مرتبطة بدفتر المحل نفسه.',
                    style: appText(11, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Surface(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: lavender,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.person_outline, color: navy),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${s.settings?['ownerName'] ?? 'صاحب المحل'}',
                          style: appText(14, weight: FontWeight.w900),
                        ),
                        Text(s.shopName, style: appText(11, color: muted)),
                        const SizedBox(height: 8),
                        const SoftTag('صاحب المحل · صلاحيات الإدارة'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Surface(child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('العاملون · حتى عاملين اثنين', style: appText(15, weight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text('يحتاج كل عامل لحساب مستقل مرتبط بالمحل وصلاحيات يحددها المالك، مع مزامنة الحركات على جميع الأجهزة.', style: appText(12, color: secondaryText)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => message(context, 'يلزم دعم إنشاء حسابات العاملين وصلاحياتهم من Backend قبل تفعيل الإضافة.'),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('إضافة عامل (تحتاج تفعيل الخدمة)'),
                ),
              ],
            )),
          ],
        ),
      ),
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
