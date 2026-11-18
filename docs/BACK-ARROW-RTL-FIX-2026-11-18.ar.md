# إصلاح سهم الرجوع في الواجهات العربية — 18 نوفمبر 2026

## السبب
كانت الترويسة المشتركة لصفحات التسجيل والاستعادة تستخدم `Icon(Icons.chevron_right)`؛ بعض أيقونات Material تُعكس تلقائيًا مع اتجاه الواجهة RTL، فتظهر متجهة لليسار رغم أن الشاشة عربية.

## التعديل
1. `lib/ui/design.dart`: استخدام `BackButtonIcon()` المخصص للرجوع بدل `Icons.chevron_right` في `BrandHeader(back: true)`.
2. `lib/features/profile.dart`: استخدام `BackButtonIcon()` بدل `Icons.arrow_back` في زر الخروج من وضع تجهيز العاملين؛ توحيد الرمز مع باقي الشاشات دون تغيير وظيفة الزر.
3. بقية الـ AppBar تستخدم زر الرجوع المدمج من Material ويختار اتجاهه تلقائيًا حسب لغة الواجهة. شاشة التقارير كانت تستخدم `BackButtonIcon()` بالفعل.
4. لم نغيّر أيقونات الانتقال إلى صفحات أخرى (`trailing: chevron_left`) لأنها ليست أزرار رجوع.

## اختبار
`flutter test test/back_button_direction_test.dart`

## خارج النطاق
- لم تتغير أي استدعاءات API، أو بيانات، أو منطق عمل، أو Configuration، أو Packages، أو Gradle، أو Android/iOS.
- لم يتوفر Flutter SDK ضمن بيئة التحرير؛ يلزم تشغيل الاختبار والتأكد بصريًا من اتجاه الأيقونة على الجهاز.
