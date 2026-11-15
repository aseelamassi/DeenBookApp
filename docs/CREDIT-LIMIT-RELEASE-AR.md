# DeenBook — سقف الدين / Credit Limit

## ما أُضيف

- حقل `CreditLimit decimal?` في الزبون. القيمة `null` أو `0` تعني حسابًا بلا سقف؛ ويُخزَّن الصفر كـ `null`.
- إنشاء/تعديل الزبون: خيارات بلا سقف، 200، 300، 500، 1000، مع حقل مخصص؛ ظهور التعديل للمالك فقط.
- `GET /api/customers`، `GET /api/parties/{id}`، `GET /api/parties/{id}/statement` و`GET /api/dashboard`: جميعها تعرض `creditLimit` في بيانات الزبون المناسبة.
- `GET /api/customers/overview`: يعيد `nearCreditLimit`.
- `GET /api/customers?filter=creditLimit`: كل الزبائن المستهلكين 80% أو أكثر من سقفهم.
- `PATCH /api/customers/{id}/credit-limit` (مالك المحل فقط): `{"creditLimit":500}` أو `{"creditLimit":null}` أو `{"creditLimit":0}`.
- بطاقات الزبائن والرئيسية وكشف الحساب: نسبة استهلاك السقف، شريط تقدم، واللون الأحمر عند 80%، والأحمر الداكن عند 100%.
- شاشة تسجيل مشتريات (دين): تحذير حي غير مانع للحفظ، يحسب صافي الدين المتوقع بعد أي دفعة مرتبطة بالمشتريات.
- فلتر محلي عند انقطاع الإنترنت يعتمد على البيانات المخزّنة (قد تكون جزئية).

## تطبيق Backend

هذه الحزمة **ملفات مصدر معدّلة فقط**؛ لا تحل محل مشروع Backend الحالي كاملًا، ولا تحتوي على `appsettings.json` أو أسرار.

1. انسخ ملفات الحزمة إلى المسارات المناظرة في مشروع Backend الحالي **بعد الاحتفاظ بنسخة احتياطية** ومراجعة الفروقات؛ لا تستبدل تغييرات أحدث على الملفات نفسها دون دمجها.
2. يحتاج الحقل الجديد عمودًا في SQL Server: `Parties.CreditLimit decimal(18,2) NULL`.
3. **الطريقة المفضلة** من Visual Studio > Package Manager Console، بعد نجاح Build، وعند اكتمال migrations القديمة:

```powershell
Add-Migration AddCustomerCreditLimit -Project DeenBook.Infrastructure -StartupProject DeenBook.Api -Context AppDbContext -OutputDir Persistence/Migrations
```

4. افتح Migration الناتج وتحقق أن `Up()` يضيف **عمود CreditLimit فقط** إلى `Parties`، وأن `Down()` يحذف ذلك العمود فقط. **إذا ظهر أي تعديل آخر على جداول أو حقول، توقف ولا تطبّق المايجريشن**؛ فقد تكون لديك مشكلة قديمة في ModelSnapshot.
5. بعد التحقق من اتصال القاعدة الصحيحة وتسجيل نسخة احتياطية، شغّل:

```powershell
Update-Database -Project DeenBook.Infrastructure -StartupProject DeenBook.Api -Context AppDbContext
```

6. اعمل Publish لمشروع `DeenBook.Api`، ثم شغّل التطبيق المعدّل. **لا تنفّذ SQL اليدوي إلى جانب EF Migration.**

تم إرفاق `ADD-CREDIT-LIMIT.sql` للمرجعية فقط: لا تنفذه إن كنت ستستخدم EF Migrations، لأن تنفيذه وحده **لا يسجّل Migration في `__EFMigrationsHistory`** وقد يتطلب تسوية لاحقة قبل توليد أي Migration آخر.

## لا تغييرات في الإعدادات

لم نغيّر إعدادات API / JWT / connection strings / Gradle / Codemagic أو إصدارات الحزم.

## اختبارات يدوية مطلوبة قبل النشر

- زبون جديد بلا سقف: لا يوجد تحذير مهما كان دينه.
- زبون سقفه 500: دين 399.99 طبيعي؛ 400 «اقترب من السقف»؛ 500 فما فوق «تجاوز السقف»؛ 510 يظهر تجاوز 10.
- زبون له رصيد (-50): لا يظهر تحذير.
- بيعة بـ 100 مع دفعة فورية 20: حساب التحذير يزيد الدين 80 فقط.
- تغيير السقف في كشف الحساب من جهاز المالك؛ جلبه من حساب العامل على جهاز آخر؛ منع العامل من تعديل السقف.
- فلتر قرب/تجاوز السقف يظهر العدد الصحيح في وضع الاتصال وبعد التخزين المؤقت دون إنترنت.
- التحذير لا يمنع زر حفظ البيعة ولا يغيّر رصيدها.

لم يتم تنفيذ `flutter test` أو `dotnet build` هنا لعدم توفر SDKs. هذه حزمة مصدر جاهزة للاختبار والتكامل، وليست بناءً إنتاجيًا موثّقًا.
