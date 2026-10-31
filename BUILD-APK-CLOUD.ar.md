# بناء APK من غير Android Studio

هذه حزمة خاصة ببناء واجهة DeenBook على Codemagic. المصدر نفسه كما في الإصدار 1.1.2؛ أضفنا ملف codemagic.yaml فقط وإرشادات البناء. مجلد api-update (مصدر الخادم) ليس مطلوبًا لبناء APK لذلك لم نضمه في حزمة الرفع؛ يظل موجودًا في ملف المشروع الكامل السابق وخادمك كما هو.

1. فك ضغط الملف: ستجد مجلد DeenBook-Flutter يحوي pubspec.yaml وcodemagic.yaml ومجلد android.
2. افتح GitHub Desktop: https://desktop.github.com . سجل الدخول، ثم File > Add local repository؛ اختر مجلد DeenBook-Flutter. إذا طلب إنشاء مستودع، اختر Create a Repository ثم Publish repository مع Private مفعّلًا.
3. افتح https://codemagic.io وسجل بحساب GitHub، ثم Add application وحدد مستودع DeenBook واختر Flutter.
4. سيتمكن Codemagic من قراءة codemagic.yaml. اختر سير العمل 'DeenBook Android APK (test)' ثم Start new build.
5. بعد نجاح البناء، من Artifacts حمّل app-debug.apk وثبّته على جهاز Android.

تنبيه: هذه نسخة Debug للتجربة؛ ليست للنشر في Google Play. التوقيع الرسمي يحتاج مفتاح release محفوظًا بأمان. بناء APK لا ينشر الـAPI ولا يتحقق من عمل الخادم فعلياً. لا ترفع المفاتيح أو كلمات المرور إلى GitHub.
