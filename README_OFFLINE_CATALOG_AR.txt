DeenBook — Offline catalog/settings source update (2026-11-27)
حزمة تراكمية من آخر Consolidated Review + التعديلات الجديدة. ليست نسخة إنتاج مختبرة.

ما أضيف في هذه الحزمة:
- طابور محلي مشفر عبر Storage الموجود، منفصل لكل محل ومستخدم، للإضافة والتعديل على الزبائن والموردين والأصناف وحذف الصنف وسقف الدين وإعدادات المحل والمحافظ.
- معرف GUID مسبق للعميل/المورد/الصنف قبل إرسال الطلب، ومزامنة الحركات المالية وطلبات البيانات حسب وقت التسجيل المحلي. إيقاف المزامنة عند تعارض الطلب لمنع تجاوز عملية تعتمد عليها عملية لاحقة.
- سجل OfflineCatalogReceipts في الخادم، العملية والإيصال ضمن معاملة واحدة. المقارنة قبل تعديل أو حذف سجل موجود لمنع الكتابة فوق تعديل جهاز آخر.
- عرض الطلبات الجديدة في مركز المزامنة وإلغاء الطلب المرفوض فقط إذا لم توجد تبعيات معروفة.
- استمرار سياسات المهلة (1–7 أيام عبر الإدارة) والإشعارات والحذف الناعم السابقة. لا تغييرات جديدة في pubspec أو Gradle أو SDK أو appsettings.

التثبيت على بيئة اختبار، بعد النسخ الاحتياطي:
1. دمج Backend ثم تطبيق EF migrations المتراكمة: ReleaseRemovedWorkerPhones، AddOfflineGraceDays، AddOfflineCatalogReceipts. لا تحذف جدول إيصالات المزامنة بعد بدء الاستخدام؛ فقد يؤدي إلى فقدان ضمان عدم التكرار.
2. dotnet test tests/DeenBook.Tests/DeenBook.Tests.csproj
3. نشر Backend في staging. تحقق من offlineCatalogVersion=1 في GET /api/subscription.
4. دمج Flutter ثم flutter analyze و flutter test. اختبر التحديث فوق النسخة السابقة، ولا تحذف بيانات التطبيق.
5. اختبر انقطاع الاتصال قبل وبعد اعتماد الطلب بالخادم، وإعادة تشغيل الجهاز، والتعارض من جهاز آخر، وإضافة زبون ثم دين له قبل المزامنة، وتحرير/حذف صنف، وإعدادات التحصيل.

متبقي ولم يُنفذ في هذا التحديث:
- شطب حركة مالية وتأكيد حوالة Offline مع احتساب الأرصدة بدقة، وإضافة عامل Offline (لا نخزن كلمة مرور العامل في طابور الطلبات).
- تقارير كاملة وتصدير/طباعة من بيانات محلية كاملة؛ قد تكون بعض المؤشرات أو الأرصدة المخزنة قديمة بعد مزامنة أو انقطاع مفاجئ. لا تستخدم التقارير الجزئية كرصيد نهائي.
- الانتقال إلى SQLite وترحيل البيانات وتشفيرها، واختبار الأداء على أجهزة منخفضة الذاكرة. التخزين الحالي لا يزال JSON في Secure Storage؛ لم يتم ضمان الأداء على أحجام كبيرة.
- معالجة تعارضات متقدمة وتبعيات متعددة الأجهزة، واسترداد الحركات المعلقة للعامل المحذوف، واختبارات أجهزة Android القديمة وGoogle Play.
- التسجيل الأول، تفعيل الاشتراك وتغيير كلمة المرور تحتاج اتصالاً بالخادم بطبيعتها.

التحقق: تم فحص الملفات المصدرية والمسارات وسلامة ZIP فقط. لا توجد أدوات Flutter/Dart/.NET SDK هنا، لذلك لم يتم تشغيل التحليل أو الاختبارات أو إنشاء APK/AAB. لا تنشر هذه الحزمة مباشرة إلى Production.

الملفات الجديدة/المعدلة في هذه المرحلة:
lib/core/offline_catalog.dart
lib/core/offline.dart
lib/core/api.dart
lib/core/session.dart
lib/features/sync_center.dart
test/offline_catalog_test.dart

الملفات التراكمية:
android/app/build.gradle.kts
android/app/src/main/AndroidManifest.xml
android/app/src/main/kotlin/com/deenbook/deenbook/MainActivity.kt
android/app/src/main/kotlin/com/deenbook/deenbook/SyncReminderReceiver.kt
ios/Runner/AppDelegate.swift
lib/core/api.dart
lib/core/offline.dart
lib/core/offline_catalog.dart
lib/core/offline_grace.dart
lib/core/session.dart
lib/core/storage.dart
lib/core/sync_reminders.dart
lib/features/profile.dart
lib/features/reports.dart
lib/features/shell.dart
lib/features/sync_center.dart
lib/features/transaction.dart
lib/main.dart
lib/services/report_export_guard.dart
lib/ui/widgets.dart
test/offline_catalog_test.dart
test/offline_grace_test.dart
test/offline_integration_test.dart
test/offline_test.dart
test/support/fakes.dart
test/worker_delete_sync_test.dart
test/worker_rename_sync_test.dart