# تقرير التنفيذ النهائي — نظام ERP كيان (KAYAN)

**تاريخ التقرير:** 2026-10-13
**الفرع:** `arena/0b8b25ad-erp-kayan`
**آخر التزام (HEAD):** `a04ec42` — «fix(audit): make company restore and data reset work with the append-only trail»
**الالتزامات الأخيرة الخاصة بهذه الجولة من العمل:** `27cfecd` ثم `ae97f74` ثم `804c8fc` ثم `8397970` (تقرير) ثم **`a04ec42`** (إصلاح عيبَي الاستعادة والتصفير)
**عدد الالتزامات المتقدّمة على `main` (`02b5d5e`):** 114 التزامًا (لا يوجد تأخّر)
**حجم التغيير مقابل `main`:** 182 ملفًا، +49,248 سطرًا، −879 سطرًا
**الإصدارات المنشورة:** `v1.0.1` (Latest) و`v1.0.0` — لم تُمسّ، ولم يُنشأ إصدار جديد
**بيئة التنفيذ والتحقق:** Linux sandbox، Node.js 22.22.3، npm 10.9.8، PostgreSQL 16.2، واجهة Flutter Web / Windows تُبنى وتُختبر عبر GitHub Actions فقط (لا يوجد Flutter SDK ولا Chrome ولا Windows في بيئة التنفيذ هذه)

> **قاعدة قراءة هذا التقرير**
> ✅ مكتمل ومتحقق منه فعليًا · 🟡 منفَّذ جزئيًا (أو منفَّذ ويحتاج تحققًا بشريًا) · 🔷 منفَّذ لكن **غير متحقق منه** · ❌ غير منفَّذ
> كل رقم في هذا التقرير مصدره أحد أمرين فقط: **(1)** أمر شُغِّل فعليًا، **(2)** بيانات قرأها GitHub API من تشغيلات Actions الفعلية. وما لم يُنفَّذ مكتوب صراحة أنه لم يُنفَّذ.
> ملاحظة بيئة: تنزيل سجلات نص Actions (`gh run view --log`) وتنزيل مرفقات التشغيلات (artifacts) **محجوب** من بيئة التنفيذ (`results-receiver` / `blob.core.windows.net` تردّ EOF)، ولذلك قُرئت حالة **كل خطوة** من `GitHub API` (`/runs/{id}/jobs`, `check-runs`, `/artifacts`)، والنص التفصيلي لسجلات CI متاح للمستخدم على صفحات التشغيلات نفسها.

---

## أ) الملخص التنفيذي

نظام كيان ERP أصبح **نظامًا مكتمل الأركان الخلفية والمحاسبية ويُثبت ذلك باختبارات حقيقية على قاعدة بيانات حقيقية**:

- **الحزمة الخلفية (NestJS/Prisma/PostgreSQL):** 45 جدولًا، 13 ترحيلًا (migrations) كلها إضافية (لم يُضَف ترحيل جديد في هذه الجولة: الإصلاح كله على مستوى التطبيق)، و**17 ملف اختبار وحدة = 150 اختبارًا تنجح كلها**، وبناء إنتاجي ناجح (`nest build`)، وفحص أنواع نظيف (`tsc --noEmit`).
- **السيناريو المحاسبي الكامل (دورة عمل حقيقية عبر الـAPI):** **69/69 فحصًا ناجحًا** — شراء وبيع ومرتجعات وشطب جرد وقيود افتتاحية ومراكز تكلفة وكل التقارير ومطابقتها بالدفتر، ومنع البيع بلا مخزون، ومنع الترحيل المزدوج تحت التزامن، ورفض مستخدم للقراءة فقط، وثبات سجل التدقيق حتى بـSQL، وعزل الشركات، ودورة الجلسة، والنسخ الاحتياطي والاستعادة مع نسخة أمان، وتحديد معدل محاولات الدخول.
- **سيناريو المخازن والطلبات وقوائم الأسعار:** **35/35 فحصًا ناجحًا** — مستودعات متعددة، تحويل بينها، طلب شراء وطلب بيع مع الفوترة الجزئية، قائمة أسعار تسعّر فعليًا، رفض صلاحيات.
- **CI (GitHub Actions) على HEAD نفسه (`a04ec42`):** **`Demo backup file` `38363607902` = success** (مع مرفقات: `kayan-demo-backup` 101,595 بايت، `kayan-company-backup-json` 86,885 بايت)، و**`Flutter Web & Backend CI` `38363607929`** و**`Windows package` `38363607919`** تشغيلان جديدان على الالتزام نفسه (حالتهما النهائية في القسمين «ز» و«ط»). وعلى الالتزام `804c8fc` قبله: `Flutter Web & Backend CI` `38323673384` = success، و`Windows package` `38323673427` = success (تركيب الـSetup الفعلي + تشغيل الخدمة + تشغيل الخادم المدمج + تشغيل العميل المثبَّت + دخول فعلي)، و`Demo backup file` `38361249030` = failure (وهو العيب الذي أُصلح اليوم).
- **نسخة Windows موجودة فعلًا ويمكن تنزيلها:** `KAYAN-Setup.exe` بحجم **116,238,275 بايت (110.9 MB)** على إصدار `v1.0.1` (رابط مباشر أدناه، مع SHA-256)، **وبُنيت اليوم نسخة جديدة من رأس الإصلاح `a04ec42`**: مرفق تشغيل `KAYAN-Setup` = **115,582,412 بايت (110.2 MB)** في تشغيل `38363607919` (success، مع تثبيت صامت واختبار تشغيل فعلي)، وهي **غير منشورة كإصدار** لأن النشر يحتاج وسمًا وموافقتك.
- **العيبان الحرجان السابقان (فشل 500 في استعادة نسخة الشركة JSON وفي تصفير بيانات الشركة) — أُصلحا في الالتزام `a04ec42` وأُثبت الإصلاح فعليًا:** الاستعادة عبر مسار البرنامج صارت **HTTP 201 وتكتب 1443 صفًا** والكتب متوازنة قبلها وبعدها، والتصفير صار **HTTP 200** مع نسخة أمان مُتحقَّق منها (236,028 بايت / 347 كائنًا)، و`scripts/build-demo-backup.mjs` صار **21/21** (كان 20/21)، وتشغيل **`Demo backup file` في CI صار success** على نفس الالتزام. التفاصيل الكاملة والدليل الخام في القسمين «و» و«ز».
- **العيب المتبقي الوحيد المسجَّل بوضوح:** لا شيء يحجب الإنتاج في مسار النسخ/الاستعادة بعد إصلاح اليوم؛ لكن تبقى نواقص موثّقة في القسم «ك» (أهمها: واجهات Flutter للمستودعات/الطلبات/قوائم الأسعار غير موجودة، وتقارير PDF تحتاج Chrome غير متوفر في بيئة CI/التنفيذ).
- **PR [#7](https://github.com/mohamedkamel78/ERP_KAYAN/pull/7) مفتوح للمراجعة** من هذا الفرع إلى `main`، ولم يُدمج أي شيء، ولم يُنشر أي إصدار جديد، ولم يُمَس `v1.0.1`.

---

## ب) التدقيق قبل/بعد

| المحور | قبل (اللقطة الموثقة في `docs/REQUIREMENTS_AUDIT.md` بتاريخ 2026-10-11) | بعد (رأس هذا الفرع `a04ec42`) |
|---|---|---|
| اختبارات الوحدة للخلفية | 47 اختبارًا (6 مجموعات) | **150 اختبارًا (17 مجموعة)** |
| سيناريو محاسبي حقيقي عبر الـAPI | غير موجود | **موجود وينجح 69/69** |
| سيناريو مخازن/طلبات/قوائم أسعار | غير موجود | **موجود وينجح 35/35** |
| مستودعات متعددة | غير موجودة (كان `StockMovement` بلا مستودع) | جدول `Warehouses` + خدمة مركزية + ربط بالفواتير والمخزون + تحويلات |
| طلبات شراء/بيع + قوائم أسعار | غير موجودة | كاملة (API + ترحيل + اختبارات + سيناريو) |
| واجهة النقدية/البنوك (Flutter) | غير موجودة | شاشة كاملة (3 تبويبات) — **غير مشغَّلة على واجهة حقيقية** |
| سجل التدقيق | جدول يُكتب فقط | **مشغّل قاعدة بيانات يمنع كل تعديل وكل حذف** (أُعيد إثباته اليوم بـ`psql` بعد الإصلاح: `UPDATE` ⇒ `ERROR: rows cannot be updated`، و`DELETE` ⇒ `ERROR: deleting requires an audited purge session`)، والاستعادة/التصفير تمرّان عبر خدمة تطهير مُدقَّقة واحدة |
| Setup الويندوز | `KAYAN-ERP-Setup-1.0.0.exe` = 112,008,392 بايت، **لا يحتوي PostgreSQL**، يتطلب PostgreSQL خارجية على 127.0.0.1:5432، **ولم يُختبر تثبيت على جهاز نظيف** | `KAYAN-Setup.exe` = **116,238,275 بايت**، يثبّت **قاعدة PostgreSQL مستقلة (خدمة `KAYAN_PostgreSQL` على المنفذ 5433)**، ويُختبر آليًا في CI: تثبيت صامت + خدمة + تجهيز قاعدة + تشغيل الخادم المدمج + تشغيل العميل المثبَّت + دخول فعلي |
| اختبار الويب | `flutter build web` فقط | + **فحوص متصفح حقيقي** (Playwright) على تطبيق Web أمام خادم وقاعدة حقيقيين في CI |
| التقارير | ميزان مراجعة/دفتر أستاذ/تصدير Excel | **12 تقريرًا** (ميزان، أرباح وخسائر، ميزانية عمومية، تدفق نقدي، مراكز تكلفة، أعمار مدينين/دائنين، دفتر يومية، دفتر أستاذ، أرصدة عملاء/موردين، حساب مفرد) + تصدير XLSX/CSV/طباعة |
| فحوص اللغة والترجمات | فحص يدوي | **بوابتان آليتان** في CI: `check-l10n-keys` (443 مفتاحًا × لغتين، 729 استخدامًا) و`check-dart-imports` (89 ملفًا) |

---

## ج) مصفوفة المتطلبات (حالة كل متطلب في البرومبت الأصلي)

### 1) المحاسبة العامة

| البند | الحالة | الإثبات | الفجوة |
|---|---|---|---|
| دليل حسابات هرمي متعدد المستويات، كود فريد لكل شركة، أسماء عربية/إنجليزية، لا دورات | ✅ | `accounting/chart-of-accounts.*` + `account-name.ts` + سيناريو حقيقي (30–46 حسابًا بأسماء عربية) + اختبارات وحدة | — |
| منع الترحيل إلى حساب تجميعي + تحويل الأب تلقائيًا | ✅ | سيناريو + `chart-of-accounts.service.spec.ts` | — |
| فترات مالية وسنوية، فتح/إغلاق، صلاحية الترحيل بتاريخ | ✅ | `fiscal-periods.controller.ts` + `year-end-close.controller.ts` | — |
| قيود يدوية وتلقائية بأرقام متسلسلة | ✅ | `journal-entries.*` + `document-number.service.ts` + سيناريو (قيد يدوي عبر submit/approve/post) | — |
| دورة الحالة: مسودة/مراجعة/اعتماد/ترحيل/إلغاء وفق الصلاحيات | ✅ | `journal-entries.controller.ts` (`:id/submit`, `:id/approve`, `:id/post`, `:id/cancel`, `:id/reverse`) + سيناريو | — |
| فحص التوازن قبل الترحيل + دقة الفاصلة العشرية والعملة | ✅ | `Decimal(19,4)` في كل المبالغ + رفض قيد غير متوازن (سيناريو) + ميزان المراجعة `difference = 0.0000` | — |
| عدم قابلية تعديل المرحَّل (عكس فقط) | ✅ | مسار `reverse` فقط بلا تعديل بعد الترحيل؛ مذكور في قواعد `PROJECT_KNOWLEDGE.md` §5 | لا اختبار آلي يحاول تعديل قيد مرحَّل مباشرةً (يحاول فقط تحديث/حذف `audit_logs`) |
| مراكز التكلفة | ✅ | `cost-centers.controller.ts` + تقرير `reports/cost-centers` + قيد مركز تكلفة في السيناريو | — |
| الأرصدة الافتتاحية (وإدخال واحد فقط) | ✅ | `opening-balances.*` + سيناريو: ترحيل أرصدة افتتاحية ورفض مجموعة ثانية | — |
| الإقفال السنوي | 🟡 | `year-end-close.controller.ts` + `GET /fiscal-periods/:id/closing-preview` **شُغِّل حيًّا** وأعاد: `totals = {revenue 750.0000, expenses 900.0000, result −150.0000}` و`blockers` (3 مسودات داخل الفترة) | **`POST /:id/close-year` لم يُنفَّذ ولا مرة على قاعدة حقيقية** (كان ضمن السيناريو سابقًا؟ لا — لا يوجد ذكره في سكربت السيناريو)، فهو 🔷 عمليًا |

### 2) التقارير (10+)

| البند | الحالة | الإثبات | الفجوة |
|---|---|---|---|
| التقارير المطلوبة كلها موجودة | ✅ | `/reports/{trial-balance, profit-and-loss, balance-sheet, cash-flow, general-journal, general-ledger, account-ledger/:id, cost-centers, receivables-aging, payables-aging, customer-balances, supplier-balances}` | — |
| مطابقة القيم بالدفتر | ✅ | السيناريو يقرأ كل تقرير ويقارنه بالقيود؛ `difference = 0.0000` | — |
| فلاتر (من/إلى/الفرع/الحساب) | ✅ | `from/to/branchId` في خدمة التقارير + فلترة الحساب في `account-ledger` | فلتر الفرع مدعوم في الـAPI؛ **لم يُختبر من الواجهة** |
| Drill-down إلى المستند المصدر | 🟡 | سطور القيود تحمل مرجع المستند والنوع (`JournalEntry.source*`) وتُصدَّر | لا يوجد اختبار آلي «نقر من التقرير إلى المستند» في الواجهة |
| Excel حقيقي | ✅ | `exports/:report/download` + `writers.spec.ts` (خلايا رقمية/تاريخية حقيقية، RTL، إجماليات) + مرفقات/فحوص سابقة | — |
| الطباعة | ✅ | `exports/:report/print` HTML عربي RTL بترويسة الشركة | — |
| PDF | 🔷 | المسار موجود (`exports/:report/pdf`) لكن الخادم يجيب فعليًا: `{"formats":["xlsx","csv"],"pdfOnTheServer":false}` + سجل: «No browser found on this machine…» | **لا Chrome في بيئة التنفيذ ⇒ لم يُنتَج PDF ولا مرة**. الزر يُخفى بصدق في الواجهة |

### 3) الأطراف والنقدية والبنوك

| البند | الحالة | الإثبات | الفجوة |
|---|---|---|---|
| عملاء وموردون (اتصال، شروط سداد، حد ائتمان) | ✅ | `parties/customers.*` و`parties/suppliers.*` + ترحيل `20261013090000_party_payment_terms` + سيناريو | — |
| أرصدة افتتاحية للأطراف | ✅ | عبر سندات الأرصدة الافتتاحية + السيناريو | — |
| فواتير/إشعارات مدين/دائن/مرتجعات | ✅ | `sales/invoices` + `purchases/invoices` + `returns/{sales,purchases}` + السيناريو (مرتجع بيع ومرتجع شراء يحرّكان المخزون والتكلفة والحسابات) | — |
| قبض ودفع + عدة خزائن وبنوك | ✅ | `cash/accounts`, `cash/vouchers` + شاشة Flutter جديدة | الشاشة **غير مشغَّلة على API حقيقي** (لا Flutter هنا) |
| تحويلات بين الخزائن/البنوك | ✅ | `cash/transfers` + السيناريو (تحويل بين صندوق وبنك) | — |
| كشوف حساب وأعمار الديون | ✅ | `cash/accounts/:id/statement` + `reports/receivables-aging` و`reports/payables-aging` + السيناريو | — |
| التسوية البنكية | 🟡 | `/cash/reconciliations` يعمل ويجيب `{"items":[],"total":0}` (تحقق حي مباشر) + `unmatched/:cashAccountId` موجود | **تدفق التسوية الكامل (إنشاء مطابقة + اعتمادها) لم يُختبر** ⇒ 🔷 عمليًا |
| ربط كل حركة بمستندها وقيدها + لا ترحيل مزدوج | ✅ | السيناريو: «posting the same invoice twice at the same moment posts it exactly once — statuses 201 and 400» + «the race did not take the stock out twice» | — |

### 4) المخزون والمشتريات والمبيعات

| البند | الحالة | الإثبات | الفجوة |
|---|---|---|---|
| أصناف/تصنيفات/باركود/وحدات بمعامل تحويل | ✅ | `inventory/items`, `categories`, `items/:id/units` + السيناريو | — |
| مستودعات متعددة لكل شركة/فرع | ✅ | `Warehouse` (companyId+branchId، افتراضي، فعال) + `inventory/warehouses` + سيناريو (إنشاء فرع ⇒ مستودع `${code}-MAIN` تلقائيًا) | لا شاشة في الواجهة |
| أرصدة افتتاحية للمخزون | ✅ | `StockDocumentKind.OPENING` + السيناريو | — |
| استلام/صرف/تحويل/تسويات/جرد | ✅ | `StockDocumentKind = {ADJUSTMENT, TRANSFER, COUNT, OPENING}` + `stock-documents` (create/post/reverse) + تحويل بين مستودعين في السيناريو + شطب جرد يمسّ حساب فروق المخزون | — |
| طلبات شراء/بيع وفواتيرهما ومرتجعاتها | ✅ (خلفيًا) | `purchases/orders`, `sales/orders` (approve/cancel/invoice بفوترة جزئية) + 35/35 في السيناريو | **لا شاشات** لها في Flutter |
| قوائم الأسعار والخصومات والضرائب | ✅ (خلفيًا) | `sales/price-lists` + `resolvePrice` + السيناريو: «the invoice total follows the price the list produced, plus the company tax rate — tax 16.8000, total 136.8000, rate 14» | **لا شاشات** لها في Flutter |
| ربط المخزون بالحسابات (GL) | ✅ | كل حركة مخزون تُنتج قيدها في نفس المعاملة؛ تسوية فروق المخزون 5107 | — |
| منع المخزون السالب افتراضيًا + تجاوز بصلاحية موثقة | ✅ | `allowNegativeStock=false` في اختبارات السيناريو: «Not enough stock… 0.0000 available, 5.0000 requested» و«the refused invoice is left as a draft with nothing posted» | الشرط «بتجاوز موثق» غير مُختبر بحالة تجاوز مفعّلة |
| تقييم مخزون موحّد وموثّق | ✅ | الإعداد `WEIGHTED_AVERAGE` + `inventory/reports/valuation` + مطابقة قيمة الدفتر (`value`/`ledgerValue`) | — |
| تقارير: أرصدة/حركة صنف/تقييم/بطيئة الحركة/حد الطلب | ✅ | `inventory/stock`, `stock/:itemId/ledger`, `reports/{valuation,slow-moving,reorder}` | — |

### 5) الشركات والفروع

| البند | الحالة | الإثبات | الفجوة |
|---|---|---|---|
| ملف شركة AR/EN + شعار + بيانات اتصال | ✅ | `company/profile` + `company/logo` (BYTEA، تحقق magic، ≤2MB) + شاشة إعداد | — |
| مقر رئيسي وفروع مرتبطة به | ✅ | `company/branches` + `kind: HEADQUARTERS` أو `BRANCH` + رفض مقر رئيسي ثانٍ + منع الدوران في شجرة الوحدات | — |
| تعديل بصلاحية | ✅ | `admin.company.manage` على مسارات التعديل | — |
| ربط المستخدمين/المخازن/الخزائن/المستندات بالفروع | ✅ | `branchId` على المستودعات والخزائن والمستندات + `createBranch` ينشئ المستودع الافتراضي داخل نفس المعاملة | ربط المستخدم بالفروع (`userBranch`) موجود في المخطط؛ لم تُختبر سيناريوهات تقييد المستخدم بفرع |
| عزل صارم بين الشركات | ✅ | `companyId` على كل جدول + السيناريو: «a user of another company sees none of this company data — customers 0, invoices 0, direct fetch 404» | — |
| ترقيم آمن لكل فرع | 🟡 | `document-number.service.ts` يعمل داخل معاملة | الترقيم «لكل فرع» لم يُختبر بعزل (الترقيم عمليًا لكل شركة/مستند) |

### 6) المستخدمون والصلاحيات

| البند | الحالة | الإثبات | الفجوة |
|---|---|---|---|
| أدوار مخصصة + صلاحيات مفصّلة (عرض/إضافة/تعديل/حذف/اعتماد/ترحيل/تصدير) | ✅ | `admin/roles`, `admin/permissions`, `admin/users` + `permissions.ts` | — |
| نطاق الوحدة/الشركة/الفرع | 🟡 | الصلاحيات على مستوى الوحدة مفعّلة وتحرس كل مسار (`RequirePermissions`)، والشركة معزولة | تقييد الفرع للمستخدم غير مُختبر |
| فصل المهام (SoD) | ✅ | السيناريو: مستخدم للقراءة فقط لا يستطيع الترحيل ولا إنشاء صنف (403) | — |
| سجل تدقيق إضافي فقط ومحمي من المستخدم العادي | ✅ | **مشغّل قاعدة بيانات** يرفض UPDATE/DELETE، والسيناريو: «the audit log refuses to be edited or deleted, even with SQL — update refused true, delete refused true, 41 rows before and 41 after» | — |
| جلسات: دخول/خروج/انتهاء/تحديث الرمز | ✅ | السيناريو: refresh يمدّد الجلسة، logout ينجح، **إعادة استخدام رمز بعد الخروج ⇒ 401** | — |
| كلمات مرور مُهشَّرة | ✅ | Argon2id (`argon2.verify` في `auth.service.ts`) | — |
| تسجيل محاولات الدخول الفاشلة دون تسريب أسرار | ✅ | `audit.record({action:'LOGIN_FAILED', entity:'users', ipAddress, userAgent})` بلا كلمة مرور + `failedLoginCount` + قفل مؤقت + رسالة موحّدة | — |
| فرض على مستوى الـAPI | ✅ | `JwtAuthGuard` + `RequirePermissions` + السيناريو يحاول كل شيء عبر HTTP | — |
| تحديد معدل الطلبات | ✅ | `rate-limit.guard.ts` + السيناريو: «6 rejected, rate limited: true» | العدّاد في الذاكرة (نسخة واحدة) — موثّق كقيد تصميم |
| تغيير كلمة المرور | 🟡 | `POST /admin/users/:id/password` (إداري) | **لا يوجد مسار «تغيير كلمتي» للمستخدم نفسه**، ولا استرجاع كلمة مرور بالبريد ⇒ ❌ جزئي |

### 7) الويب/الخادم المركزي

| البند | الحالة | الإثبات | الفجوة |
|---|---|---|---|
| Flutter Web ← NestJS مركزي ← PostgreSQL واحد | ✅ في CI | تشغيل `Browser checks` في CI: خادم حقيقي + قاعدة hq + تطبيق web حقيقي في متصفح (artifact `browser-checks` 813,208 بايت) | لم يُختبر على شبكة حقيقية خارج بيئة CI |
| إعدادات dev/test/prod | ✅ | `.env` + `NODE_ENV` + `KAYAN_*`؛ إعدادات الأمثلة موجودة | لا ملفات env مرفوعة (وهذا صحيح أمنيًا) |
| CORS مقيّد | ✅ | `common/config/cors.ts`: قائمة `CORS_ORIGINS` + عناوين خاصة (localhost/127/10/192.168/172.16-31/.local) + رفض أي أصل آخر في الإنتاج | لم يُختبر من متصفح على جهاز آخر |
| HTTPS/TLS | ❌ | غير مُنفَّذ داخل التطبيق (يُنصح بإنهائه عبر وكيل عكسي) | لا اختبار TLS |
| عدم تسريب أسرار في حزمة JS | ✅ (تحليل) | الأسرار تُقرأ من `.env` في الخادم فقط؛ الواجهة تستدعي الـAPI ولا تحمل مفاتيح | لا فحص آلي (scanner) لحزمة الويب في CI |
| توثيق on-prem/منافذ/سحابة/VPN/وكيل عكسي + عدم تعريض PostgreSQL | 🟡 | `README.md` + `docs/DESKTOP_WINDOWS.md` + `docs/BACKUP_RESTORE.md` | **لا يوجد دليل نشر سحابي/VPN/وكيل عكسي مكتوب** بعد |
| بقاء بناء Windows يعمل | ✅ | CI `Windows package` = success على HEAD | — |
| اختبار محلي/شبكة داخلية/خارجي حقيقي | 🟡 | محلي: ✅ (كل السيناريوهات)؛ الشبكة الداخلية: الخادم يعرض عنوانًا داخليًا (`/health/network`) | **الوصول الخارجي/VPN/TLS لم يُختبر إطلاقًا** |

### 8) لوحة المعلومات

| البند | الحالة | الإثبات | الفجوة |
|---|---|---|---|
| مبيعات/مشتريات/مصروفات/ربح/سيولة | ✅ | `dashboard/summary` + شاشة `dashboard_screen.dart` + السيناريو يقرأ اللوحة | — |
| أرصدة الأطراف والفواتير المتأخرة وتنبيهات المخزون | ✅ | حقول `overdue`, `stock`, `cashPosition` في الرد + السيناريو | — |
| مقارنات فترات + فلاتر | 🟡 | الفترة مدعومة في الـAPI | مقارنة الفترات من الواجهة غير متحققة |
| حالات فارغة صريحة وعدم عرض بيانات تجريبية كأنها حقيقية | ✅ | السيناريو: «الحالة الفارغة لفترة لا شيء فيها» + `hasData` في الرد + `test/widget/dashboard_screen_test.dart` | — |

### 9) تجربة الاستخدام (UX)

| البند | الحالة | الإثبات | الفجوة |
|---|---|---|---|
| الحفاظ على التصميم (أخضر `#0B6E4F`/جداول كثيفة/RTL) | ✅ | `DESIGN.md` + الشاشات كما هي | — |
| RTL/LTR | ✅ | `Directionality` + `dir="rtl"` في الطباعة + فحوص `flutter test` في CI | — |
| تمرير/تنقل للقوائم الطويلة | 🟡 | الشاشات تعتمد قوائم مُرقَّمة/تمرير قياسي | **لا تحقق بصري** (لا Flutter هنا) |
| بحث/تصفية/فرز/ترقيم صفحات | 🟡 | البحث والتصفية موجودان على نطاق واسع في الشاشات (وحقل `searchHint` في نماذج القوائم) والـAPI يدعم `q/status/from/to/limit`؛ والفرز/الترقيم المحلي مذكور صراحة في شاشتين (`admin_screen.dart`, `parties_screen.dart`) | الفرز/الترقيم غير مُعمَّم على كل الشاشات، ولأنه لا Flutter هنا فلا تحقق بصري |
| رسائل خطأ عربية/إنجليزية واضحة ودون تفاصيل داخلية | ✅ للواجهة | السيناريو يقيس الرسائل الآمنة (401 موحّد بلا كشف وجود المستخدم) | **رسائل التحقق من الـAPI إنجليزية** (موثّق في `PROJECT_KNOWLEDGE.md` §7) |
| حالات تحميل/نجاح/فشل + تأكيدات | ✅ | `state_views.dart` + `confirmAction` + اختبارات widget | — |
| إدخال بلوحة المفاتيح + جودة الطباعة/التصدير | 🟡 | دعم `Tab` قياسي في النماذج + طباعة A4 موثقة | لا اختبار آلي للإدخال بلوحة المفاتيح |

### 10) النسخ الاحتياطي والاستعادة والترقية

| البند | الحالة | الإثبات | الفجوة |
|---|---|---|---|
| نسخ مجدولة + استبقاء | ✅ | `BackupScheduleService` (فحص كل 15 دقيقة، الفاصل والاستبقاء في `company_settings`) + السيناريو: «interval 24h, retention 5, next 2026-10-14T07:05:50Z» | لم يُنفَّذ فاصل زمني قصير حقيقي لملاحظة نسختين متتاليتين |
| موقع محمي وموثق | ✅ | `KAYAN_BACKUP_DIR` (في ويندوز: `%APPDATA%\KAYAN-ERP\backups`) + `docs/BACKUP_RESTORE.md` | — |
| التحقق من السلامة | ✅ | قراءة الأرشيف بـ`pg_restore --list` (350 كائنًا) قبل الاعتماد عليه | — |
| استعادة مُبرهَنة على قاعدة اختبار منفصلة | ✅ | السيناريو: «restoring into scratch database kayan_restore_check_…» + نسخة أمان + «after the restore the data is still there» | — |
| نسخة شركة JSON (نقل بين منشآت) | ✅ **مُصلَح ومُتحقَّق منه** | `build-demo-backup.mjs` = **21/21** وسطر الاستعادة «HTTP 201, total written=1443»، وكان التوقّع `HTTP 500` قبل الالتزام `a04ec42`. وفي CI: تشغيل `Demo backup file` `38363607902` = **success** بعد أن كان failure | لا فجوة |
| تصفير بيانات الشركة | ✅ **مُصلَح ومُتحقَّق منه** | تصفير حيّ: `POST /admin/reset` ⇒ **HTTP 200** (نسخة أمان 236,028 بايت/347 كائنًا + حذف فعلي مُعدَّد) ثم `POST /setup/initial` ⇒ **201** ثم دخول ناجح، والسجل يضم `AUDIT_PURGED` + `RESET` | لا فجوة |
| الترقية عبر الإصدارات | 🟡 | سكربتات التثبيت تحافظ صراحةً على بيانات الاعتماد وأسرار JWT عند الترقية (`manage-kayan-db.ps1:295`)، والنسخ التراكمية إضافية | **لم تُختبر ترقية فعلية من إصدار أقدم إلى أحدث** (لا اختبار CI لها) |

### 11) الاختبارات (يُفصّل في القسم «ز»)

| البند | الحالة |
|---|---|
| `flutter analyze` / `flutter test` / `flutter build web` | ✅ في CI (لا SDK محليًا) |
| اختبارات NestJS وحدة/خدمة/API | ✅ **150/150 محليًا** (17 مجموعة) + CI (Backend Tests & Build = success على `a04ec42`) |
| سيناريو محاسبي حقيقي على PostgreSQL | ✅ 69/69 |
| سيناريو مخازن/طلبات/قوائم أسعار | ✅ 35/35 |
| بناء إنتاجي NestJS + بناء Web | ✅ |
| بناء Windows/Setup | ✅ CI (+ اختبار تثبيت وتشغيل فعلي) |
| اختبار تدفق الدخول/الجلسة/الصلاحيات | ✅ (سيناريو) |
| اختبار العزل متعدد الشركات | ✅ |
| اختبار النسخ/الاستعادة | ✅ للـpg_dump/الاستعادة الكاملة · ❌ لمسار JSON للشركة |
| اختبارات التزامن ومنع التكرار | ✅ (نفس اللحظة) |
| اختبار AR/EN + RTL | 🟡 (تشغيل اختبارات Flutter في CI ينجح؛ لا تحقق بصري) |
| اختبار على متصفح حقيقي + خادم + قاعدة | ✅ CI Browser checks |
| تثبيت على جهاز نظيف | ✅ على runner CI · ❌ على جهاز مستخدم نهائي |

### 12) GitHub

| البند | الحالة |
|---|---|
| فرع تطوير مستقل والتزامات منطقية | ✅ `arena/0b8b25ad-erp-kayan` |
| الحفاظ على `v1.0.1` | ✅ لم تُمسّ الإصدارات ولا الوسوم |
| فتح Pull Request | ✅ **[#7](https://github.com/mohamedkamel78/ERP_KAYAN/pull/7)** مفتوح للمراجعة من هذا الفرع إلى `main` (ولم يُدمج) |
| عدم الدمج في `main` دون موافقة | ✅ لا دمج — PR مفتوح فقط |
| عدم إصدار جديد قبل نجاح الاختبارات | ✅ لا إصدار جديد؛ والاختبارات وCI كلها ناجحة على رأس الفرع (`a04ec42`)، ولم يُنشأ إصدار رغم ذلك لأن ذلك يحتاج موافقة صريحة |

---

## د) تفاصيل التغييرات التقنية (أهم الملفات)

### الالتزام `a04ec42` — «fix(audit): make company restore and data reset work with the append-only trail» (9 ملفات، +984/−85)
| الملف | التغيير | لماذا |
|---|---|---|
| `backend/src/common/audit/audit-purge.service.ts` | **جديد (≈330 سطرًا موثّقًا)** | المصدر الوحيد الذي يُعلن جلسة تطهير (`set_config('kayan.allow_audit_purge','on', is_local=true)` داخل معاملة المتصل)، بسببين معلنين فقط، ويسجّل `AUDIT_PURGED` داخل نفس المعاملة. وفيه `detachUserLinks` التي تُفرّغ روابط المستخدمين المحذوفين بإعادة كتابة الصف كما هو (نفس `id`/`createdAt`) لأن كل `UPDATE` مرفوض. |
| `backend/src/common/audit/audit.module.ts` | تسجيل/تصدير | حقن الخدمة في مساري النسخ والتصفير |
| `backend/src/modules/backup/backup.service.ts` | `RestoreOptions` (الفاعل/IP/User-Agent)، `RestoreClient`، وكل الكتابات عبر عميل المعاملة، ونافذة تطهير تُغلَق قبل أي إدراج، وسجل التطهير بعد إعادة الحسابات | يجعل الاستعادة **ذرّية فعلًا** وقابلة للتنفيذ على قاعدة فيها سجلات تدقيق |
| `backend/src/modules/backup/backup.controller.ts` | تمرير هوية الفاعل | ليسمّي السجل شخصًا لا حدثًا |
| `backend/src/modules/admin/reset.service.ts` | استدعاء التطهير مع تفريغ روابط المستخدمين قبل حذفهم + تصحيح تعليق | إصلاح 500 في التصفير |
| `backend/src/modules/company/setup.service.ts` | تقاعد الحسابات الزائدة (`isActive=false`+`deletedAt`) بدل حذفها، وعدم حذف شركة خاملة لها سجل تدقيق | منع نفس النوع من الـ500 في مسار الإعداد الأولي |
| `backend/src/modules/backup/backup.service.spec.ts` | 6 ⇒ 15 اختبارًا (ترتيب التفريغ، كتابة السجل بعد إعادة الحسابات، عميل المعاملة فقط، رفض سبب غير معلن، عدم تسجيل تطهير لم يحدث، مدير مُستبدَل) | إثبات السلوك لا الشكل |
| `backend/src/modules/admin/reset.service.spec.ts` | 15 ⇒ 18 اختبارًا (ثلاث جمل تفريغ الروابط بترتيبها + الرقم في سجل التطهير) | إثبات الترتيب الصحيح |
| `backend/scripts/build-demo-backup.mjs` | يطبع مقتطفًا من سجل الخادم عند الإخفاق | يشرح السبب في التشغيل نفسه بدل تخمينه |

### الالتزام `8397970` — «Docs: the final implementation report»
`ERP_KAYAN_FINAL_IMPLEMENTATION_REPORT.md` (هذا الملف، 600 سطر) + `backend/scripts/build-demo-backup.mjs` (أول نسخة من شارح سجل الخادم).

### الالتزام `804c8fc` — «Tidy the cash screen»
`lib/features/cash/presentation/screens/cash_screen.dart` (جسم الطلب صار خريطة واضحة `body['allocations']`، تلميح «الأقدم أولًا» بجوار حقل المبلغ، حذف `Consumer` زائد).

### الالتزام `ae97f74` — «Warehouses, orders and price lists, with the screens and the proof» (35 ملفًا)
- الخلفية: `backend/src/common/warehouse/{warehouse.module,warehouse.service,warehouse.service.spec}.ts` (خدمة عامة `@Global` بحلّ المستودع الافتراضي `${branch.code}-MAIN` وإنشائه عند الحاجة)، `backend/src/modules/inventory/warehouses.controller.ts`، `backend/src/modules/sales/price-lists.{service,controller,service.spec}.ts`، `sales/sales-orders.*`، `purchases/purchase-orders.*`، تعديل `stock-documents.service.ts` + خدمتي الفواتير لتخزين `warehouseId`، وربط `sales.module.ts`/`purchases.module.ts`.
- قاعدة البيانات: ترحيل `20261014090000_warehouses_orders_price_lists` (مستودعات، طلبات، قوائم أسعار، أعمدة ربط).
- الاختبارات: `backend/scripts/scenario-warehouses-orders.mjs` (35 فحصًا).
- الواجهة: وحدة نقدية كاملة `lib/features/cash/presentation/{providers/cash_providers.dart, screens/cash_screen.dart}` + 27 مفتاح ترجمة في `app_ar.arb` و`app_en.arb` + الملفات المولَّدة الثلاثة + مسار `/cash` في `app_router.dart` وعنصر التنقّل في `erp_shell.dart`.
- البوابات: `tools/check-l10n-keys.mjs`، وتشغيل بوابتي l10n/imports في `.github/workflows/web-ci.yml`.

### الالتزام `27cfecd` — «Accounting, cash, inventory and reporting completed; proven by a real scenario» (61 ملفًا)
وحدات كاملة: `modules/accounting/*` (cost-centers، opening-balances، settings، year-end-close، account-map، document-number، posting، fiscal-periods)، `modules/cash/*` (controller + 4 خدمات: حسابات/سندات/تحويلات/تسويات)، `modules/inventory/*`، `modules/reports/*` (12 تقريرًا)، `modules/dashboard/*`، `modules/returns/*`، `modules/admin/reset.*`، `modules/health/*`، `common/config/{cors,jwt-secrets}.*`، `common/guards/*`، `common/filters/*`، `common/download-ticket.ts`، `prisma/migrations/20261012233000_accounting_cash_inventory_completion` (+5 ترحيلات أخرى)، `prisma/{permissions,seed-permissions,seed-demo}.ts`، `scripts/{apply-migrations,scenario-accounting,build-demo-backup,api-check}.mjs`، وواجهات Flutter (تحديث `api_client.dart`, `browser_actions*`, `token_store`, شاشات اللوحة/التقارير/الفواتير)، وتمديد `.github/workflows/web-ci.yml` (+100 سطر: مهام السيناريو وفحوص المتصفح) و`windows-package.yml`، ثم في هذا الفرع عمومًا (التزامات سابقة ضمن نفس الخط): `.github/workflows/demo-backup.yml` (`b350cf1`) و`scripts/smoke-test-installed-windows.ps1` (`88f04a7`).

### ضمن نفس الفرع (قبل ذلك): إصلاحات ويندوز والنسخ الاحتياطي
`windows-package.yml` (بناء Windows + Inno Setup + اختبار تثبيت فعلي)، حزمة أدوات PostgreSQL داخل البرنامج، `scripts/{install-kayan-database,manage-kayan-db}.ps1` (خدمة `KAYAN_PostgreSQL` على 5433 مع الحفاظ على البيانات والأسرار عبر الترقيات)، وإصلاح تسجيل الدخول من العميل المثبَّت إلى خادمه المحلي.

---

## هـ) تقرير وحدوي لكل وحدة

### المحاسبة ودليل الحسابات
شجرة حسابات بلا حدود عمق، كود فريد لكل شركة، نوع حساب + `isPostable`، منع الترحيل على التجميعي، منع الحذف مع الحركات أو الأبناء (والبديل: تعطيل)، اقتراح الكود تلقائيًا (`suggest-code`)، وترتيب أسماء الحسابات (المفضّل ← الآخر ← الكود) في خدمة واحدة تُستخدم في الشاشات والتقارير والتصدير. **الإثبات:** السيناريو + اختبارات وحدة.

### القيود والفترات والترحيل
قيود تلقائية من كل مستند (فاتورة/سند/تحويل/مخزون/افتتاحي) وقيود يدوية بدورة submit→approve→post وقيد عكسي فقط بعد الترحيل. فحص توازن قبل الترحيل + ربط بالفترة + رقم تسلسلي. الأرصدة الافتتاحية تُدخل مرة واحدة وتُمنع الثانية. الإقفال السنوي له معاينة حقيقية تعرض الإيرادات والمصروفات والنتيجة والعوائق (مسودات داخل الفترة) قبل الإقفال.

### التقارير
12 تقريرًا خلفيًا، كلها تُبنى من سطور القيود (لا أرقام محسوبة موازية)، مع تصدير XLSX/CSV/طباعة، وترويسة شركة وشعار اختياري. PDF يحتاج Chrome على الخادم (المسار موجود ويكشف عن نفسه بصدق عبر `capabilities`).

### الأطراف والنقدية والبنوك
عملاء/موردون بشروط سداد وحدود ائتمان، أرصدة، كشوف، أعمار ديون، سندات قبض/دفع تُخصَّص على أقدم الفواتير المفتوحة، عدة خزائن وبنوك، تحويلات، وتسوية بنكية (المسارات موجودة، والتدفق لم يُختبر كاملًا).

### المخزون والتقييم
مستودعات لكل فرع (مع إنشاء الافتراضي تلقائيًا للفروع القديمة وللفروع الجديدة داخل معاملة الإنشاء)، حركات مخزون من كل مستند، متوسط مرجّح موثّق، حساب فروق المخزون، منع الرصيد السالب افتراضيًا، وتقارير رصيد/حركة/تقييم/بطيء الحركة/حد إعادة الطلب.

### المشتريات والمبيعات
طلبات شراء وبيع بحالات `DRAFT/APPROVED/PARTIALLY_FULFILLED/FULFILLED/CANCELLED`، اعتماد بمراعاة فصل المهام، إلغاء، وفوترة جزئية لا تتجاوز المتبقي، وقوائم أسعار بخصومات تُطبَّق في ترتيب واضح: السعر المكتوب ← قائمة الطرف ← سعر الصنف.

### الشركات والفروع
ملف شركة بالعربية والإنجليزية + شعار في القاعدة (BYTEA) + مقر رئيسي واحد + فروع بتسلسل أب/ابن ومنع الدوران، وربط المستودعات/الخزائن/المستندات بالفرع، و**عزل صارم بالشركة مُثبَت**.

### المستخدمون والصلاحيات
أدوار مخصصة، صلاحيات مفصّلة على 7 أنواع عمليات، حراسة كل مسار على مستوى الـAPI، Argon2id، جلسات JWT مع تحديث وإبطال، قفل بعد محاولات فاشلة مع تدقيق `LOGIN_FAILED` بلا أسرار، تحديد معدل، وسجل تدقيق **لا يمكن تعديله أو حذفه حتى بـSQL**.

### لوحة المعلومات
ملخّص واحد يعطي المبيعات والمشتريات والسيولة وأرصدة الأطراف والمتأخرات والمخزون مع علم `hasData`، وحالة فارغة صريحة، وشاشة Flutter لها اختبار widget.

### النسخ والاستعادة
نسخ مجدولة (فاصل واستبقاء من إعدادات الشركة) + نسخ يدوي + تحقق بقراءة الأرشيف + استعادة إلى قاعدة مؤقتة أولًا + نسخة أمان + فحص سلامة بعد الاستعادة، **كلها ناجحة في السيناريو**. ومسارا «نسخة الشركة JSON» و«تصفير بيانات الشركة» كانا معطوبين (500) وأُصلحا في `a04ec42` وأُثبتا: **21/21** و`HTTP 201` (1443 صفًا) للاستعادة، و`HTTP 200` + إعداد أولي `201` للتصفير، مع بقاء الحماية نفسها ترفض أي `UPDATE`/`DELETE` من خارج جلسة التطهير.

### الويب + ويندوز
Web يُبنى ويُختبر في CI بمتصفح حقيقي أمام خادم وقاعدة، وWindows يُبنى ويُختبر تثبيتًا وتشغيلًا، مع خادم Node مدمج وPostgreSQL خاص وحفظ إعدادات في `%ProgramData%\KAYAN-ERP`.

---

## و) التحقق المحاسبي والمالي (نتائج فعلية)

### 1) السيناريو المحاسبي الكامل — `node scripts/scenario-accounting.mjs http://127.0.0.1:3101/api/v1`
**النتيجة: 69/69 فحصًا ناجحًا** (يعمل اليوم 2026-10-13 على PostgreSQL 16.2 حقيقية وقاعدة `kayan_scenario`). مقتطفات من المخرجات الفعلية:

- شراء 10 وحدات ثم بيع 4: المخزون وتكلفة البضاعة والضريبة 14% والإيراد — كلها مطابقة للدفتر.
- **رفض البيع بلا مخزون:** `400 — Not enough stock for …: 0.0000 available, 5.0000 requested`، و**بقيت الفاتورة مسودة ولم يُرحَّل شيء** (`status draft`).
- **منع الترحيل المزدوج تحت التزامن:** «posting the same invoice twice at the same moment posts it exactly once — statuses 201 and 400» و«the race did not take the stock out twice — on hand 3».
- مرتجعات بيع وشراء وشطب جرد وقيود افتتاحية ومراكز تكلفة: كلها تتحرك في المخزون والحسابات معًا.
- كل التقارير قُرئت وقُورنت بالدفتر؛ ميزان المراجعة: `difference 0.0000`.
- **سجل التدقيق:** «41 audit rows» لكل تغييرات السيناريو، و**«the audit log refuses to be edited or deleted, even with SQL — update refused true, delete refused true, 41 rows before and 41 after»**.
- **عزل الشركات:** «a user of another company sees none of this company data — customers 0, invoices 0, direct fetch 404».
- **الجلسات:** تحديث رمز ينجح، خروج ينجح، **إعادة استخدام رمز بعد الخروج ⇒ 401**، وطلب بلا رمز ⇒ 401.
- **الترحيلات:** «every migration is applied and none is left pending — 13 migrations, 0 pending».
- **النسخ الاحتياطي:** نسخة مجدولة `kayan-full-2026-10-13-07-05-50.dump` موثّقة القراءة (350 كائنًا)، نسخة يدوية = 176,403 بايت في 121 مللي ثانية، استعادة إلى قاعدة مؤقتة مع نسخة أمان `kayan-safety-…dump`، و«after the restore the data is still there».
- **تاريخ الاستبقاء:** «the schedule reports its interval, its retention and when it is next due — interval 24h, retention 5, next 2026-10-14T07:05:50.598Z».
- **تحديد المعدل:** «6 rejected, rate limited: true»، ورسالة لا تكشف سبب الفشل: «Too many attempts. Try again in 56 second(s).»

### 2) سيناريو المخازن والطلبات وقوائم الأسعار — `scenario-warehouses-orders.mjs`
**النتيجة: 35/35 فحصًا ناجحًا** (اليوم أيضًا، على نفس القاعدة). من المخرجات الفعلية:

- قائمة أسعار تسعّر فعليًا: «the invoice total follows the price the list produced, plus the company tax rate — tax 16.8000, total 136.8000, rate 14»؛ والسعر المكتوب يدويًا يتقدّم على القائمة: «a price that was typed is what is charged, list or no list — unit price 200.0000».
- الطلب لا يحرّك مخزونًا: «an order moves no stock: it is a promise, not a receipt — on hand 9.0000».
- الفوترة الجزئية: «the order knows it is only partly invoiced — PARTIALLY_FULFILLED, invoiced 3.0000, remaining 2.0000»، ورفض الزيادة: `400 — Line 1: only 2.0000 is still outstanding, 99.0000 was asked for`، ثم `FULFILLED` ورفض فاتورة أخرى.
- منع الفاتورة من طلب غير معتمد: `400 — Approve the order before invoicing it`.
- الصلاحيات: مستخدم ضيّق يقرأ المستودعات (200) ويُرفض عن إدارتها (`403 — Missing permission: inventory.warehouses.manage`) وعن شاشات الطلبات (`403 — Missing permission: purchases.orders.create`).
- سجل التدقيق يغطي الشاشات الجديدة: `price_lists 4, purchase_orders 6, sales_orders 3, warehouses 2`.

### 3) بناء نسخة العرض والتحقق منها — `node scripts/build-demo-backup.mjs`
**النتيجة بعد الإصلاح: 21/21 — كل الفحوص ناجحة** (وكانت 20/21 قبل الالتزام `a04ec42`):
```
PASS  the company JSON backup restores cleanly through the company restore route — HTTP 201, total written=1443
21/21 checks passed
```
والسطران الحاكمان من نفس التشغيل:
```
PASS  the demo books balance before they are backed up — 28 accounts with movement, debits 29413788.7900 / credits 29413788.7900, difference 0.0000
PASS  the restored books balance, and match what was backed up — debits 29413788.7900 (backed up 29413788.7900), difference 0.0000
```
ونجح معه: بناء كتب الشركة الوهمية المتوازنة (46 حسابًا، 163 قيدًا/490 سطرًا، 46 فاتورة بيع، 20 فاتورة شراء، 14 عميلًا، 9 موردين، 30 صنفًا، 90 صف مخزون، 29,413,788.79 مدين = 29,413,788.79 دائن)، ونسخ pg_dump (235,609 بايت، 347 كائنًا)، ونسخة JSON (839,483 بايت)، واستعادة الـdump عبر مسار البرنامج (HTTP 201، بمدقّق ومُختبر في قاعدة مؤقتة)، وأن الكتب بعد الاستعادة مطابقة لما نُسخ.

### 4) السبب الجذري للإخفاقين، والإصلاح، والدليل الحيّ (الالتزام `a04ec42`)

**العَرَضان:** `POST /api/v1/backup/restore?replace=true` و`POST /api/v1/admin/reset` يعيدان **HTTP 500** على أي شركة لديها سجلات تدقيق. المعاملة تتراجع بالكامل، فلا فقد بيانات (تحقق: عدد الحسابات بقي 32 قبل وبعد الفشل).

**السبب الجذري (مُثبَت بالنص الكامل من سجل PostgreSQL 16.2 محليًا، مع `log_statement='all'`):** جدول `audit_logs` محميّ بمشغّل `kayan_audit_logs_append_only`، وهذا نصه الفعلي المقروء من قاعدة البيانات:
```sql
IF TG_OP = 'UPDATE' THEN RAISE EXCEPTION 'audit_logs is append-only: rows cannot be updated';
IF TG_OP = 'DELETE' AND coalesce(current_setting('kayan.allow_audit_purge', true),'off') <> 'on'
  THEN RAISE EXCEPTION 'audit_logs is append-only: deleting requires an audited purge session'; END IF;
```
أي أن **أي `UPDATE` ممنوع دائمًا** (حتى مع جلسة التطهير)، و`DELETE` مسموح فقط داخل جلسة تطهير. ودقق الأمران ثلاثة أشياء لم تكن متوافقة معه:
1. **لا شيء في البرنامج كان يُعلن جلسة تطهير** (`grep -rn "allow_audit_purge" src/` كان بلا نتائج) ⇒ `DELETE FROM audit_logs` يفشل دائمًا.
2. **حذف مستخدم** يجعل PostgreSQL نفسه ينفّذ `UPDATE audit_logs SET "userId" = NULL` (لأن المفتاح الأجنبي `ON DELETE SET NULL`) ⇒ والمشغّل يرفض كل `UPDATE` بحكم التصميم. (هذا العَرَض أُعيد إنتاجه معزولًا: `id=` نفس الاتصال، الإعداد `on`، ومع ذلك: `ERROR: audit_logs is append-only: rows cannot be updated`. واختبار مضاد: `UPDATE` لا يطابق أي صف يمرّ — لأن المشغّل `FOR EACH ROW` — وهذا ما حسم التشخيص.)
3. **حذف صفوف مرتبطة داخل معاملة عبر عميل الجذر (pooled)** بدل عميل المعاملة نفسها، وهو ما كان يجعل الاستعادة غير ذرّية.

**الإصلاح (6 ملفات، بلا أي ترحيل جديد وبلا أي تغيير في مشغّل قاعدة البيانات أو في حمايته):**
| الملف | ما تغيّر |
|---|---|
| `backend/src/common/audit/audit-purge.service.ts` | ملف جديد: الخدمة الوحيدة التي تُعلن تطهيرًا. `set_config('kayan.allow_audit_purge','on', is_local=true)` داخل معاملة المتصل (لا تتسرّب)، بسبب من مجموعة مغلقة (`company-json-restore`/`company-data-reset`)، وتسجيل `AUDIT_PURGED` داخل نفس المعاملة بحيث **لا يحدث تطهير لا يمكن تسجيله**. وفيها `detachUserLinks`: تُفرّغ روابط المستخدمين المحذوفين بالطريقة الوحيدة التي تسمح بها الحماية — نسخ الصفوف إلى جدول مؤقت، حذفها تحت الجلسة المُدقَّقة، ثم إعادة كتابتها بنفس `id` و`createdAt` وبلا العمود الرابط. **الصفوف لا تُعدَّل أبدًا**؛ وما يخصّ شركة أخرى يبقى كما هو. |
| `backend/src/common/audit/audit.module.ts` | تسجيل الخدمة وتصديرها |
| `backend/src/modules/backup/backup.service.ts` | كل الكتابات (حذف/إدراج) تمرّ الآن بعميل المعاملة ⇒ الاستعادة ذرّية فعلًا؛ الحذف كله داخل النافذة المُدقَّقة؛ سجل التطهير يُكتب بعد إعادة الحسابات (لأنه يسمّي المدير، والاستبدال يستبدل الحسابات)، وإن اختفى حساب المدير نفسه يبقى معرّفه في `afterJson` بدل ربط مفتاح أجنبي بمستخدم غير موجود |
| `backend/src/modules/backup/backup.controller.ts` | تمرير هوية الفاعل (`userId`/IP/User-Agent) إلى الاستعادة ليُسمّى الشخص في السجل |
| `backend/src/modules/admin/reset.service.ts` | خطوة التدقيق تستدعي التطهير مع تفريغ روابط المستخدمين قبل حذفهم؛ وتصحيح تعليق يوضّح أن صفوف التدقيق غير التابعة لشركة (مثل نسخة كاملة للقاعدة) تبقى — فهي أحداث على مستوى التركيب لا تاريخ هذه الشركة |
| `backend/src/modules/company/setup.service.ts` | الحسابات الإدارية الزائدة تُتقاعَد (`isActive=false`, `deletedAt`) بدل حذفها، وشركة خاملة لها سجل تدقيق لا تُحذف — لأن حذفها كان سيجعل المفتاح الأجنبي يحاول تعديل سجل التدقيق فترفضه الحماية |
| `backend/scripts/build-demo-backup.mjs` | عند أي إخفاق يطبع الآن مقتطفًا من سجل الخادم (بعد إزالة الألوان) ليشرح السبب في التشغيل نفسه |

**الدليل الحيّ على الإصلاح:**
1. `scripts/build-demo-backup.mjs`: **21/21** (سطر الاستعادة: `HTTP 201, total written=1443`)، والكتب متوازنة قبل النسخ وبعد الاستعادة (`debits 29413788.7900`، الفرق `0.0000`).
2. **تصفير حقيقي على نسخة مؤقتة من القاعدة** (`kayan_reset_probe`، وليس على بيانات المستخدم): `GET /admin/reset` أعاد معاينة صحيحة، و`POST /admin/reset` أعاد **HTTP 200** مع: نسخة أمان مُتحقَّق منها `kayan-full-2026-10-13-07-33-48.dump` = 236,028 بايت / 347 كائنًا، وحذف فعلي (163 قيدًا و490 سطرًا و46 فاتورة بيع و20 فاتورة شراء و266 حركة مخزون و90 رصيدًا و5 متتاليات ترقيم)، ثم سجل التدقيق بعد العملية:
```
AUDIT_PURGED  audit_logs  reason=company-data-reset
RESET         company_data
CREATE        companies      (setup الجديد)
LOGIN         users
```
3. **بعد التصفير عاد شاشة الإعداد الأولى وعملت**: `GET /setup/status` ⇒ `{"needsSetup":true,"companyCount":0,"hasUsers":true}`، و`POST /setup/initial` ⇒ **HTTP 201** (أعاد نفس معرّف الشركة `de26160e-…` وأعاد إنشاء الدليل المحاسبي: 30 حسابًا)، ثم **الدخول نجح** بالحساب المدير ⇒ وهو تحقق حقيقي لدورة «تصفير ثم إعداد من جديد». وأُعيد التصفير ثانية بنجاح (السلوك متكرر بلا تراكم).
4. **الحماية نفسها ما زالت قائمة بعد الإصلاح** (من `psql` مباشرة على نفس القاعدة):
```
UPDATE audit_logs SET action='tampered' WHERE action='RESET'
  → ERROR: audit_logs is append-only: rows cannot be updated
DELETE FROM audit_logs WHERE action='RESET'
  → ERROR: audit_logs is append-only: deleting requires an audited purge session
```
5. **اختبارات الوحدة:** 150 اختبارًا في 17 مجموعة (كانت 135) — منها في `backup.service.spec.ts`: ترتيب تفريغ الروابط قبل حذف المستخدمين، وإثبات أن سجل التطهير يُكتب **بعد** إعادة الحسابات، وأن الاستعادة لا تكتب إلا عبر عميل المعاملة، وأن عملية تطهير بسبب غير معلن تُرفَض، وأن الفشل لا يُسجَّل كتطهير تم.

### 5) لقطة أخرى حيّة (الإقفال السنوي)
`GET /accounting/fiscal-periods/:id/closing-preview` على فترة مفتوحة أعاد فعليًا:
```
totals: {"revenue":"750.0000","expenses":"900.0000","result":"-150.0000","resultLabel":"loss"}
blockers: ["5 draft sales invoice(s) fall inside this period","1 draft purchase invoice(s)…","1 draft opening balance(s)…"]
```
أي أن المعاينة تعمل وتعطي أرقامًا حقيقية من الدفتر ومنع الإقفال مع وجود مسودات.

---

## ز) نتائج الاختبارات والبناء (بأرقامها، مع الإخفاقات وغير المنفَّذ)

### أ) نتائج محلية أُعيد إنتاجها اليوم على رأس الفرع `a04ec42`

| الأمر | النتيجة | الزمن |
|---|---|---|
| `npx jest --silent` (في `backend/`) | **17 ملف اختبار / 150 اختبارًا — كلها ناجحة** (كانت 135 قبل الالتزام `a04ec42`) | 17.2 ثانية |
| `npx tsc --noEmit` | نظيف | — |
| `npm run build` (`nest build`) | ناجح، `dist` = 3.7 MB | 11 ثانية |
| `node scripts/scenario-accounting.mjs` | **69/69** (على رأس `804c8fc`؛ وأُعيد تشغيله على `a04ec42` داخل CI: success) | 6.2 ثانية |
| `node scripts/scenario-warehouses-orders.mjs` | **35/35** (نفسه في CI على `a04ec42`: success) | 63.6 ثانية |
| `node scripts/build-demo-backup.mjs` | **21/21 — كل الفحوص ناجحة** (كانت 20/21 قبل الإصلاح) | 28.6 ثانية |
| تصفير حقيقي عبر الـAPI على نسخة مؤقتة (`probe` محلي، ليس على بيانات المستخدم) | **HTTP 200** + نسخة أمان مُتحقَّق منها (236,028 بايت/347 كائنًا) + إعداد أولي جديد **HTTP 201** + دخول ناجح | ثانيتان |
| `node tools/check-l10n-keys.mjs` | ناجح: **443 مفتاحًا في اللغتين، 729 استخدامًا، كل مفتاح موجود في الملفات المولّدة** | — |
| `node tools/check-dart-imports.mjs` | ناجح: **89 ملف Dart، كل استيراد/تصدير يشير إلى ملف موجود** | — |
| تحقق حيّ إضافي | `/cash/reconciliations` ⇒ `{"items":[],"total":0}` · `/exports/capabilities` ⇒ `{"formats":["xlsx","csv"],"pdfOnTheServer":false}` · `/health/network` يعلن عنوان الشبكة الداخلية | — |

**مقياس الكود في نفس الرأس:** الخلفية 17 ملف اختبار وحدة، 45 جدولًا، 13 ترحيلًا (7 منها جديدة مقابل `main`)؛ الواجهة 89 ملف Dart، 17 شاشة، 20 ملف اختبار Dart يحوي **117 اختبارًا معلنًا** (العدّ نصّي من الملفات، لأن `flutter test` نفسه يُشغَّل في CI لا هنا).

### ب) نتائج CI على نفس الالتزام `a04ec42` (وما قبله للمقارنة)

| التشغيل | الرابط | الحالة | أهم ما نُفّذ |
|---|---|---|---|
| Demo backup file — `38363607902` | https://github.com/mohamedkamel78/ERP_KAYAN/actions/runs/38363607902 | ✅ **success** (كان failure قبل الإصلاح) | كل الخطوات ناجحة: قاعدة PostgreSQL + بناء الخادم + **بناء نسخة العرض والتحقق من استعادتها** (السطر `21/21` هو نفسه المطبوع محليًا لأن السكربت واحد) + نشر JSON للتنزيل + بصمة + 3 مرفقات. |
| Flutter Web & Backend CI — `38363607929` | https://github.com/mohamedkamel78/ERP_KAYAN/actions/runs/38363607929 | ✅ **success** | الوظائف الأربع كلها success وبلا أي خطوة غير ناجحة: `Flutter Web Build` (بوابتا اللغة والاستيرادات + `flutter analyze` + `flutter test` + `flutter build web --release`)، `Accounting scenario (real database)` (قاعدة حقيقية + الخادم + سيناريو المحاسبة + سيناريو المخازن والطلبات)، `Backend Tests & Build`، و`Browser checks` (خادم وتطبيق Web حقيقيان في متصفح). |
| Windows package — `38363607919` | https://github.com/mohamedkamel78/ERP_KAYAN/actions/runs/38363607919 | ✅ **success** (بناء جديد من رأس الإصلاح) | كل خطوات البناء والاختبار ناجحة: `Install Flutter`، `Build the program folder and the single installer`، **`Install and smoke-test the actual setup and local server`**، `Check that the result is really shippable`، `Check that the only deliverable exists`، `Keep the single installer on this run`. وخطوة النشر `skipped` كما هو متوقع (ليست وسمًا)، وخطوة التوقيع نُفِّذت بنجاح مع تحذير (لا شهادة) ⇒ الملف الناتج **غير موقَّع**. مدة التشغيل: 12.5 دقيقة. |
| Windows package — `38323673427` (على `804c8fc`) | https://github.com/mohamedkamel78/ERP_KAYAN/actions/runs/38323673427 | ✅ **success** | بناء الحزمة + **تثبيت صامت فعلي واختباره**: خدمة `KAYAN_PostgreSQL` من `%ProgramData%\KAYAN-ERP\pgsql`، أدوات PostgreSQL تعمل، `prepare-database.mjs` ينجح، `/health` ⇒ `status=ok, database=up`، ثم تشغيل `erp_kayan.exe` المثبَّت وحده يقلع خادمه المحلي ويؤدي الدخول. التوقيع: خطوة نُفِّذت وانتهت بنجاح مع تحذير (شهادة غير مضبوطة) ⇒ الملف **غير موقَّع**. |
| Flutter Web & Backend CI — `38323673384` (على `804c8fc`) | https://github.com/mohamedkamel78/ERP_KAYAN/actions/runs/38323673384 | ✅ success | نفس الوظائف الأربع بنجاح |
| Demo backup file — `38323673341` (على `804c8fc`) | https://github.com/mohamedkamel78/ERP_KAYAN/actions/runs/38323673341 | ❌ failure | العيب الذي أُصلح اليوم (كان الإخفاق الوحيد في CI؛ وبعد الإصلاح صار success كما في أول جدول). |

**مرفقات التشغيلات (متاحة للتنزيل من صفحة التشغيل، وغير منتهية):**

| المرفق | التشغيل | الحجم |
|---|---|---|
| `KAYAN-ERP-web` | 38363607929 (الجديد على `a04ec42`) | 14,583,659 بايت |
| `accounting-scenario-log` | 38363607929 | 8,288 بايت |
| `browser-checks` | 38363607929 | 812,277 بايت |
| `kayan-demo-backup` | 38363607902 (جديد) | 101,595 بايت |
| `kayan-company-backup-json` | 38363607902 (جديد) | 86,885 بايت |
| `kayan-demo-backup-log` | 38363607902 (جديد) | 1,427 بايت |
| `KAYAN-Setup` | **38363607919 (جديد، من رأس الإصلاح `a04ec42`)** | **115,582,412 بايت (110.2 MB)** |
| `KAYAN-Setup` (السابق) | 38323673427 | 115,596,351 بايت |

> **تحذير منهجي:** حصيلة كل خطوة أعلاه مقروءة من GitHub API (`/jobs` و`/check-runs`)، أما **النص المطبوع داخل سجلات CI** فلم أستطع تنزيله من بيئة التنفيذ (الحجب المذكور في الأعلى)، لذلك لا أنسب أي رقم مطبوع داخل CI، والأرقام العددية كلها من تشغيلي المحلي.

### ج) الإخفاقات بالتفصيل

**لا يوجد أي إخفاق متبقٍ في هذه الجولة.** الإخفاقان الوحيدان المسجَّلان سابقًا (`Demo backup file` و`POST /admin/reset` — كلاهما خطأ 500) أُصلحا في الالتزام `a04ec42` وأُعيد تشغيل CI فأصبح success، وأُثبت الإصلاح محليًا (21/21 + تصفير حيّ). الإخفاقات الثانوية الموثقة تاريخيًا: 1. **بوابة «هذا الجهاز يملك أدوات PostgreSQL»** في `build-demo-backup.mjs` تفشل إن لم تُضبط `KAYAN_PG_DUMP`/`KAYAN_PG_RESTORE` ولا وُجدت الأدوات (حدث معي في أول تشغيل ثم نجح بعد الضبط) — سلوك مقصود ومفيد. 4. **قيود بيئية:** لا PDF (لا Chrome)، لا تشغيل لواجهة Flutter محليًا، لا تنزيل سجلات CI.

### د) ما لم يُنفَّذ إطلاقًا (ولماذا)

| البند | السبب |
|---|---|
| `flutter analyze` / `flutter test` / `flutter build web` محليًا | لا يوجد Flutter SDK في بيئة التنفيذ — **لكنها نُفِّذت بنجاح في CI** |
| PDF فعلي | لا Chrome/Chromium — والبرنامج نفسه يعلن ذلك عبر `capabilities` |
| تشغيل شاشة النقدية (أو أي شاشة) على API حقيقي | لا Flutter Run هنا |
| الإقفال السنوي الفعلي (`close-year`) والتسوية البنكية الكاملة | لم يشملهما السيناريو، ولم أُنفّذهما يدويًا لأن التعليمات منعت إعادة التطوير/التوسّع في التنفيذ |
| ترقية فعلية من إصدار أقدم | لا اختبار CI لها؛ لا جهاز Windows هنا |
| الوصول عبر LAN/VPN/HTTPS من جهاز آخر | لا شبكة ممتدة في بيئة التنفيذ |
| تثبيت على جهاز مستخدم نهائي | البيئة لا تملك Windows؛ CI يثبّت على runner نظيف فقط |

---

## ح) الأمن وسلامة البيانات

- **الصلاحيات تُفرض على الـAPI** (ليست إخفاء واجهة): `RequirePermissions` على كل مسار تقريبًا، والسيناريو يحاول كل شيء عبر HTTP ويُرفض 403. ✅
- **عزل الشركات:** كل جدول يحمل `companyId`، والسيناريو يثبت أن مستخدم شركة أخرى يرى صفرًا ويأخذ 404 على الاستدعاء المباشر. ✅
- **كلمات المرور:** Argon2id؛ ولا كلمة مرور في أي رد أو سجل؛ ومحاولات الفشل تُسجَّل كتدقيق `LOGIN_FAILED` مع IP/User-Agent وبلا أي سر، مع قفل مؤقت بعد تكرار الفشل؛ ورسالة موحّدة تمنع تعداد الحسابات. ✅
- **الجلسات:** JWT access/refresh، الرموز المخزنة hashed في القاعدة، تجديد يعمل، خروج يُبطل، وإعادة استخدام بعد الخروج تُرفض. ✅
- **حد المعدل:** عدّاد نوافذ ثابتة في الذاكرة، حصة ضيّقة لـ`/auth/login` و`/auth/refresh`، ويحتاج `TRUST_PROXY=true` خلف وكيل عكسي (موثّق في الشيفرة). 🟡 (نسخة واحدة)
- **سجل التدقيق:** إضافي فقط، ومحمي **على مستوى قاعدة البيانات** بمشغّل يرفض **كل** UPDATE (حتى داخل جلسة التطهير) وكل DELETE خارج جلسة تطهير مُدقَّقة. أُعيد إثبات ذلك اليوم بعد الإصلاح من `psql` مباشرة على قاعدة فيها بيانات:
```
UPDATE audit_logs SET action='tampered' WHERE action='RESET'
  → ERROR: audit_logs is append-only: rows cannot be updated
DELETE FROM audit_logs WHERE action='RESET'
  → ERROR: audit_logs is append-only: deleting requires an audited purge session
INSERT ⇒ مسموح (السجل ينمو فقط)
```
  و**التصفير/الاستعادة لا يفتحان الحماية أكثر مما يلزم**: الجلسة المُدقَّقة تُفعَّل بـ`set_config(..., is_local=true)` داخل معاملة العملية نفسها (تنتهي بانتهاء المعاملة أو تراجعها)، ولا تُفعّلها أي شيفرة أخرى (`grep -rn "allow_audit_purge" src/` ⇒ موضع واحد فقط)، ولا تُقبل إلا بسببين معلنين، ويُكتب سجل `AUDIT_PURGED` **داخل نفس المعاملة** فلا يمكن أن يحدث تطهير لا يمكن تسجيله. وصفوف التدقيق لا تُعدَّل أبدًا: الروابط إلى مستخدم محذوف تُفرَّغ بإعادة كتابة الصف كما هو بلا عمود الرابط (نفس `id` ونفس `createdAt`) وهذا ما يجعل «UPDATE ممنوع» ممكنًا. ✅
- **الأسرار:** فحص نصّي على الملفات المتعقَّبة (`git grep` على أنماط كلمات مرور في الروابط، والمفاتيح الخاصة، ورموز AWS/OpenAI) لم يجد أي سر حقيقي؛ ووجد فقط بيانات اعتماد **حاويات CI المؤقتة** (`postgres:postgres@127.0.0.1:5432` داخل `web-ci.yml` و`demo-backup.yml`) — وهي ليست أسرار إنتاج لأنها تعيش داخل تشغيل مؤقت، لكن الأفضل نقلها إلى `secrets`. ولم أُدخل أي سر جديد في هذه الجولة. ✅
- **الشعار/المرفقات:** تحقق magic-byte وحد 2MB قبل التخزين في القاعدة (BYTEA). ✅
- **الترحيلات إضافية وقابلة للتنفيذ على قاعدة قائمة:** 13 ترحيلًا، لا حذف جدول/عمود، وطريقة التطبيق `apply-migrations.mjs` (معاملة لكل ترحيل + بصمة SHA-256)، و`prisma migrate deploy` يبقى no-op في هذه البيئة. ✅
  - ما هو **غير مُختبَر**: ترحيل قاعدة قديمة مليئة بالبيانات عبر الجولة كاملة ثم العودة (rollback) — لا يوجد اختبار استرجاع ترحيل (وسياسة المشروع: لا rollback، بل استعادة من نسخة).
- **سلامة البيانات عند الفشل:** عملية تصفير فاشلة (قبل الإصلاح) **لم تفقد شيئًا** (تحققت: 32 حسابًا وفترة وفرع قبل وبعد)، لأن كل شيء داخل معاملة. ✅ وبعد الإصلاح: التصفير الحيّ نجح على **نسخة مؤقتة من القاعدة** فقط (`kayan_reset_probe`) بعد نسخة أمان مُتحقَّق منها، ولم يُمَس أي بيانات مستخدم حقيقية. ✅
- **الاستعادة ذرّية فعليًا الآن:** كل حذف وإدراج داخل الاستعادة يمرّ عبر عميل المعاملة نفسه (`RestoreClient`) بدل عميل الجذر المُجمَّع، وله اختبار وحدة يمنع العودة إلى العميل الجذري. ✅
- **النسخ الاحتياطي:** نسخة أمان تُؤخذ قبل أي استعادة، وقاعدة مؤقتة تُجرَّب قبل الاستعادة الحقيقية، وفحص سلامة بعدها. ✅
- **مخاطر متبقية:** (1) لا HTTPS داخل التطبيق نفسه (يُضبط خلف وكيل عكسي خارجي — موثّق في `docs/DESKTOP_WINDOWS.md`)؛ (2) عدّاد المعدل في الذاكرة (نسخة خادم واحدة)؛ (3) توقيع الشيفرة غير مُفعَّل (SmartScreen سيحذّر)؛ (4) مزامنة ملفات الترجمة اليدوية (`app_en/app_ar` + `generated/`)؛ (5) سجلات «النسخة الكاملة للقاعدة» تُكتب بلا `companyId` (حدث على مستوى التركيب) فلا تظهر في شاشة تدقيق شركة بعينها. لا شيء مما سبق يمنع الاستخدام الإنتاجي، وكلها مسجّلة في القسم «ك». 

---

## ط) جاهزية الإنتاج والنشر

### 1) حالة الخادم/الـAPI/قاعدة البيانات (بيئة التنفيذ)
- PostgreSQL 16.2 على `127.0.0.1:55432` (تُثبَّت هنا من حزمة `pgserver` للاختبار فقط؛ **ليست** طريقة الإنتاج).
- قاعدتان مستعملتان: `kayan_scenario` (13 ترحيلًا مطبَّقة، 0 معلقة)، و`kayan_json` للتحقق، وقواعد مؤقتة تُنشأ وتُحذف أثناء الاستعادة (`kayan_restore_check_*`).
- الخادم: `node dist/src/main.js` على المنفذ 3101/3102، ويعرض نفسه: `KAYAN-API-READY port=… host=0.0.0.0`.
- الإنتاج المستهدف على ويندوز: خدمة `KAYAN_PostgreSQL` على المنفذ **5433** مع قاعدة وعمود بيانات تحت `%ProgramData%\KAYAN-ERP`، والخادم يعمل من داخل حزمة البرنامج على Node المدمج.

### 2) حالة Windows Setup (الإجابة المباشرة على سؤال «هل توجد نسخة حقيقية؟»)
**نعم — توجد نسخة منشورة وقابلة للتنزيل، وأخرى أحدث غير منشورة:**

| النسخة | الملف | الحجم | الرابط | ملاحظات |
|---|---|---|---|---|
| **المنشورة** `v1.0.1` (Latest) | `KAYAN-Setup.exe` | **116,238,275 بايت (110.9 MB)** | https://github.com/mohamedkamel78/ERP_KAYAN/releases/download/v1.0.1/KAYAN-Setup.exe | SHA-256 `1E7C22CAC9C9F7D759B0242759B11DB60DD79934974ED69F35F0EF554F391C8E` · **Authenticode: NotSigned** · بُنيت من الالتزام `2b657a6e` حسب نص الإصدار (أي **قبل** الالتزامات الثلاثة الأخيرة `27cfecd`/`ae97f74`/`804c8fc`) · مساحة غير مضغوطة 601.7 MB · `verify-package.ps1` = 53 ناجحًا/0 فاشل · تثبّت PostgreSQL خاصًا على 5433 |
| **الأحدث — بُني من رأس الإصلاح `a04ec42`** | مرفق تشغيل `KAYAN-Setup` | **115,582,412 بايت (110.2 MB)** | [صفحة التشغيل `38363607919`](https://github.com/mohamedkamel78/ERP_KAYAN/actions/runs/38363607919) ← «Artifacts» ← `KAYAN-Setup` | **غير منشور كإصدار** (النشر مشروط بوسم `v*`، ولم أنشئ وسمًا لأن ذلك يحتاج موافقة صريحة). بُني واختُبر في نفس التشغيل: تثبيت صامت + خدمة `KAYAN_PostgreSQL` + تشغيل الخادم المدمج + تشغيل العميل المثبَّت + دخول. مدة التشغيل 12.5 دقيقة، وحالة كل خطوة `success`. |
| نسخة أقدم (سابقة للإصلاح) | مرفق تشغيل `KAYAN-Setup` | 115,596,351 بايت | [صفحة التشغيل `38323673427`](https://github.com/mohamedkamel78/ERP_KAYAN/actions/runs/38323673427) ← Artifacts | من الالتزام `804c8fc` |
| إصدار أقدم | `KAYAN-Setup.exe` على `v1.0.0` | 116,229,334 بايت | https://github.com/mohamedkamel78/ERP_KAYAN/releases/download/v1.0.0/KAYAN-Setup.exe | — |

**حالة نسخة اليوم (من `a04ec42`):** بُنيت بنجاح واختُبرت في CI بنفس السلسلة أدناه (كل الخطوات `success`)، وحجمها **115,582,412 بايت**، وهي قابلة للتنزيل من صفحة التشغيل، **لكنها لم تُثبَّت على جهاز المستخدم ولم تُختبر ترقية عليها** — أما التنزيل من رابط مباشر ثابت فيحتاج نشر إصدار، وهو قرارك.

**ما تم اختباره فعليًا على نسخة Windows (على الالتزامين `804c8fc` و`a04ec42`):** ✅ تثبيت صامت على runner نظيف، ✅ قيام خدمة PostgreSQL مستقلة والتحقق من مسارها في ProgramData، ✅ تشغيل أدوات `psql/pg_dump/pg_restore/postgres` من الحزمة، ✅ كتابة ملف الإعدادات المشترك `kayan.env`، ✅ تجهيز القاعدة (`prepare-database.mjs`)، ✅ إقلاع الخادم المدمج و`/health` = «ok/up»، ✅ **تشغيل `erp_kayan.exe` المثبَّت وحده ⇒ أقلع خادمه المحلي وصار healthy**، ✅ تسجيل دخول فعلي `/auth/login` ثم `/auth/me`.
**ما لم يُختبر:** ❌ إزالة (uninstall)، ❌ **ترقية فعلية فوق نسخة أقدم**، ❌ تفاعل GUI بالنقر (اختبارات CI تتعامل مع الـAPI لا مع الأزرار)، ❌ التثبيت على جهاز المستخدم نفسه، ❌ التحقق من التوقيع (الملف غير موقَّع => ستحذّر SmartScreen).

### 3) نسخة الويب
تُبنى في CI (`flutter build web --release`) ويُحفظ ناتجها كمرفق، وتُختبَر في متصفح حقيقي مع خادم وقاعدة. لا استضافة/HTTPS في هذه البيئة.

### 4) المتطلبات اليدوية المتبقية قبل إعلان «جاهز للإنتاج»
1. ~~إصلاح مسار استعادة JSON للشركة (و`admin/reset`)~~ — **تم في `a04ec42`**، وتشغيل `Demo backup file` صار أخضر ✅ (يبقى اختياريًا: اختبار استعادة على جهاز ويندوز حقيقي).
2. **مراجعة PR [#7](https://github.com/mohamedkamel78/ERP_KAYAN/pull/7)** والموافقة الصريحة على الدمج في `main` (لم تُطلب بعد، ولم يُدمج شيء).
3. قرار بشأن توقيع الشيفرة (شهادة) لتفادي تحذيرات SmartScreen.
4. اختبار ترقية حقيقي من `v1.0.1` على جهاز اختبار ويندوز.
5. إنهاء HTTPS/CORS لبيئة الشبكة الحقيقية (وكيل عكسي موثّق).
6. تجهيز دليل نشر (on-prem/VPN/سحابة) — غير مكتوب بعد.

---

## ي) معلومات GitHub والتسليم

| البند | القيمة |
|---|---|
| المستودع | https://github.com/mohamedkamel78/ERP_KAYAN |
| الفرع | `arena/0b8b25ad-erp-kayan` (مرفوع، لا تأخّر عن `origin`) |
| آخر التزام | **`a04ec42`** «fix(audit): make company restore and data reset work with the append-only trail» |
| الالتزامات الأخيرة | `27cfecd` · `ae97f74` · `804c8fc` · `8397970` (التقرير) · **`a04ec42`** (إصلاح العيبين) |
| Pull Request | ✅ **[#7 — ERP كيان: إكمال الوحدات + إصلاح استعادة الشركة وتصفير البيانات](https://github.com/mohamedkamel78/ERP_KAYAN/pull/7)** من `arena/0b8b25ad-erp-kayan` إلى `main` — **مفتوح للمراجعة، ولم يُدمج ولم يُطلب دمجه**. (PRs أخرى: [#6](https://github.com/mohamedkamel78/ERP_KAYAN/pull/6) [#5](https://github.com/mohamedkamel78/ERP_KAYAN/pull/5) [#4](https://github.com/mohamedkamel78/ERP_KAYAN/pull/4) [#3](https://github.com/mohamedkamel78/ERP_KAYAN/pull/3) — والمدمجة: #2 و#1) |
| تشغيلات Actions على HEAD (`a04ec42`) | Web+Backend [38363607929 ✅](https://github.com/mohamedkamel78/ERP_KAYAN/actions/runs/38363607929) · Demo backup [38363607902 ✅](https://github.com/mohamedkamel78/ERP_KAYAN/actions/runs/38363607902) · Windows [38363607919](https://github.com/mohamedkamel78/ERP_KAYAN/actions/runs/38363607919) (النتيجة والحجم في «ط») |
| تشغيلات الالتزام السابق (`804c8fc`) | Web+Backend [38323673384 ✅](https://github.com/mohamedkamel78/ERP_KAYAN/actions/runs/38323673384) · Windows [38323673427 ✅](https://github.com/mohamedkamel78/ERP_KAYAN/actions/runs/38323673427) · Demo backup [38323673341 ❌](https://github.com/mohamedkamel78/ERP_KAYAN/actions/runs/38323673341) |
| الإصدارات | [v1.0.1](https://github.com/mohamedkamel78/ERP_KAYAN/releases/tag/v1.0.1) (Latest, untouched) · [v1.0.0](https://github.com/mohamedkamel78/ERP_KAYAN/releases/tag/v1.0.0) |
| وسم↔التزام | `v1.0.1` → `02b5d5e` (main) · `v1.0.0` → `2d11baaf` |
| ملفات الإصلاح الأخير | `backend/src/common/audit/audit-purge.service.ts` (جديد) · `backend/src/common/audit/audit.module.ts` · `backend/src/modules/backup/backup.service.ts` · `backend/src/modules/backup/backup.controller.ts` · `backend/src/modules/backup/backup.service.spec.ts` · `backend/src/modules/admin/reset.service.ts` · `backend/src/modules/admin/reset.service.spec.ts` · `backend/src/modules/company/setup.service.ts` · `backend/scripts/build-demo-backup.mjs` |
| ملفات مفتاحية | `backend/prisma/schema.prisma` · `backend/prisma/migrations/20261014090000_warehouses_orders_price_lists/` · `backend/src/common/warehouse/warehouse.service.ts` · `backend/src/modules/sales/price-lists.service.ts` · `backend/src/modules/cash/cash.controller.ts` · `backend/scripts/{scenario-accounting,scenario-warehouses-orders,build-demo-backup,apply-migrations}.mjs` · `lib/features/cash/presentation/screens/cash_screen.dart` · `tools/check-l10n-keys.mjs` · `.github/workflows/{web-ci,windows-package,demo-backup}.yml` · `scripts/smoke-test-installed-windows.ps1` · `docs/{REQUIREMENTS_AUDIT,BACKUP_RESTORE,DEMO_BACKUP,DESKTOP_WINDOWS}.md` · `PROJECT_KNOWLEDGE.md` |
| التوقيع | غير موقَّع (`NotSigned`) — خطوة التوقيع في CI تنفّذ تحذيرًا وتخرج بنجاح عند غياب `KAYAN_SIGNING_CERT_*` |

---

## ك) النواقص والمخاطر وخطة الإغلاق

| # | النقص/الخطر | الأثر الحقيقي | خطوة الإغلاق | الأولوية |
|---|---|---|---|---|
| ~~1~~ | ~~**استعادة نسخة الشركة JSON تفشل (500)**~~ — **أُغلق في `a04ec42`** | كان: لا يمكن نقل شركة بين منشآت عبر JSON، وCI أحمر | أُغلق: خدمة تطهير مُدقَّقة + تفريغ روابط المستخدمين + كتابة عبر عميل المعاملة + سجل بعد إعادة الحسابات؛ والدليل: `build-demo-backup.mjs` **21/21** وCI **success** (`38363607902`) واستعادة حيّة `HTTP 201` كتبت 1443 صفًا | ✅ مغلق |
| ~~2~~ | ~~**`POST /admin/reset` يفشل (500)**~~ — **أُغلق في `a04ec42`** | كان: «تصفير بيانات الشركة» غير قابل للاستخدام | أُغلق: تصفير حيّ `HTTP 200` + نسخة أمان مُتحقَّق منها + إعداد أولي جديد `HTTP 201` + دخول ناجح + إعادة إثبات أن الحماية ما زالت ترفض `UPDATE`/`DELETE` | ✅ مغلق |
| 3 | **لا شاشات Flutter** للمستودعات/طلبات الشراء والبيع/قوائم الأسعار (الخلفية والاختبارات موجودة) | هذه القدرات لا يستطيع المستخدم استخدامها من الواجهة | بناء شاشات على غرار شاشة النقدية + توسيع السيناريو/golden tests | **عالية** |
| 4 | شاشة النقدية الجديدة **لم تُشغَّل على API حقيقي** | أخطاء مسارات/حقول محتملة في الواجهة | تشغيل يدوي على جهاز فيه Flutter، أو اختبار تكامل في CI يرسم الشاشة ويستدعي الـAPI | **عالية** |
| 5 | **لم يُدمج الفرع في `main`** (PR [#7](https://github.com/mohamedkamel78/ERP_KAYAN/pull/7) مفتوح للمراجعة) | عمل الفرع ليس في الفرع الرئيسي بعد | مراجعة والموافقة صراحةً على الدمج | متوسطة |
| 6 | **الترقية بين الإصدارات غير مختبرة** | خطر غير مُقاس عند ترقية جهاز عميل من `v1.0.1` إلى الأحدث (رغم أن سكربتات الترقية تحافظ على القاعدة والأسرار) | اختبار ترقية آلي في CI: تثبيت نسخة قديمة ⇒ بيانات ⇒ تثبيت الجديدة ⇒ التحقق من بقاء البيانات والدخول | **عالية** |
| 7 | PDF غير مُتحقَّق منه (لا Chrome) | زر PDF مُخفى افتراضيًا على أجهزة بلا Chrome | تشغيل `/exports/:report/pdf` على جهاز فيه Chrome/Chromium مرة واحدة وتوثيق الناتج | متوسطة |
| 8 | **Installer غير موقَّع** | تحذير SmartScreen وربما منع تشغيل لدى بعض العملاء | شهادة توقيع + تفعيل أسرار `KAYAN_SIGNING_CERT_*` | متوسطة |
| 9 | لا HTTPS داخل التطبيق ولا دليل نشر (VPN/وكيل عكسي/سحابة) | الوصول الخارجي غير آمن/غير مُوثَّق | وكيل عكسي (IIS/nginx) + `CORS_ORIGINS` + `TRUST_PROXY=true` + دليل مكتوب | متوسطة |
| 10 | تحديد المعدل في الذاكرة | لا يعمل عبر أكثر من نسخة واحدة خلف موازن تحميل | تخزين مشترك (Redis) عند التوسّع — موثّق حاليًا كقيد | منخفضة |
| 11 | رسائل التحقق في الـAPI إنجليزية | تجربة عربية غير كاملة عند الأخطاء | تعريب Problem Details أو خريطة رسائل | منخفضة |
| 12 | لا يوجد «تغيير كلمة مروري» أو استرجاع بالبريد | مستخدم لا يستطيع تغيير كلمته بنفسه (يستطيع الإداري) | مسار `POST /auth/password` + اختبار | متوسطة |
| 13 | إقفال السنة/التسوية البنكية بلا اختبار حقيقي | ثقة أقل في مسارين محاسبيين مهمين | إضافتهما إلى `scenario-accounting.mjs` | متوسطة |
| 14 | ترقيم المستندات «لكل فرع» غير مُختبَر بعزل | احتمال تضارب ترقيم بين الفروع | اختبار إنشاء مستندين مترافقين في فرعين والتحقق من التسلسل | منخفضة |
| 15 | سجل «النسخة الكاملة للقاعدة» (`full-backup.service.ts`) يُكتب **بلا `companyId`** | الحدث لا يظهر في شاشة تدقيق شركة بعينها (وهو حدث على مستوى التركيب، ولهذا لا يُبطلها تصفير الشركة) | تمرير `companyId` من الطلب إلى `createFull` عند توفر سياق شركة | منخفضة |

---

## ل) تعليمات إعادة التحقق المستقلة

كل ما يلي قابل للتنفيذ على أي جهاز Linux/macOS مع PostgreSQL 14+ وNode 20+، وبدون أي إعداد خاص:

```bash
# 1) الكود على نفس الحالة
git clone https://github.com/mohamedkamel78/ERP_KAYAN.git
cd ERP_KAYAN && git checkout arena/0b8b25ad-erp-kayan   # HEAD = a04ec42

# 2) الخلفية: تبعيات + توليد Prisma + اختبارات + بناء
cd backend && npm ci && npx prisma generate
npx jest --silent                 # المتوقع: 17 ملفًا / 150 اختبارًا ناجحًا
npx tsc --noEmit                  # المتوقع: نظيف
npm run build                     # المتوقع: ناجح

# 3) قاعدة بيانات نظيفة + ترحيلات + بذور
export DATABASE_URL="postgresql://<user>:<pass>@127.0.0.1:5432/kayan_scenario?schema=public"
createdb kayan_scenario
node scripts/apply-migrations.mjs     # المتوقع: 13 ترحيلًا، 0 معلقة
npx ts-node prisma/seed.ts            # إنشاء admin / Admin@12345 (غيّرها فورًا في أي استخدام حقيقي)

# 4) تشغيل الخادم
JWT_ACCESS_SECRET=local-access JWT_REFRESH_SECRET=local-refresh KAYAN_PG_DUMP=$(which pg_dump) KAYAN_PG_RESTORE=$(which pg_restore) \
  node dist/src/main.js               # يستمع على 3000 افتراضيًا (KAYAN-API-READY)

# 5) السيناريوهات (شاهد الأرقام بنفسك)
node scripts/scenario-accounting.mjs http://127.0.0.1:3000/api/v1          # المتوقع: 69/69
sleep 60                                                                   # لتجاوز نافذة تحديد المحاولات الفاشلة
node scripts/scenario-warehouses-orders.mjs http://127.0.0.1:3000/api/v1   # المتوقع: 35/35

# 6) نسخة العرض + إثبات الاستعادة (الفحص الذي كان أحمر وصار أخضر)
#    ضع مجلد أدوات PostgreSQL على PATH أيضًا (السكربت يستدعي psql/pg_dump/pg_restore)
DATABASE_URL="postgresql://…/kayan_demo?schema=public" \
KAYAN_RESTORE_URL="postgresql://…/kayan_demo_restore?schema=public" \
ADMIN_DATABASE_URL="postgresql://…/postgres" JWT_ACCESS_SECRET=x JWT_REFRESH_SECRET=y \
KAYAN_BACKUP_DIR=/tmp/kayan-backups \
  node scripts/build-demo-backup.mjs    # المتوقع: 21/21، وسطر الاستعادة HTTP 201

# 6-ب) إثبات التصفير (على قاعدة اختبار، لا على بيانات حقيقية)
#     1) أنشئ قاعدة اختبار من نسخة:  createdb -T kayan_scenario kayan_reset_probe
#     2) شغّل الخادم عليها بـ DATABASE_URL=kayan_reset_probe و KAYAN_BACKUP_DIR
#     3) سجّل الدخول ثم:  POST /api/v1/admin/reset  {"password":"…","confirmation":"RESET"}
#        المتوقع: 200 مع backupBytes/backupEntries، ثم POST /api/v1/setup/initial ⇒ 201
#     4) وأعد إثبات الحماية نفسها من psql:
#        UPDATE audit_logs SET action='x';  ⇒ ERROR: audit_logs is append-only: rows cannot be updated
#        DELETE FROM audit_logs;            ⇒ ERROR: … deleting requires an audited purge session
#        (اذهب إلى https://github.com/mohamedkamel78/ERP_KAYAN/blob/arena/0b8b25ad-erp-kayan/ERP_KAYAN_FINAL_IMPLEMENTATION_REPORT.md#و-التحقق-المحاسبي-والمالي-نتائج-فعلية)
#        ملاحظة: كلا الأمرين يجب أن يفشل — أي نجاح لأحدهما يعني أن الحماية ضعفت.

# 7) الواجهة (على جهاز فيه Flutter)
flutter pub get && flutter analyze && flutter test && flutter build web --release

# 8) بوابتا الجذر
node tools/check-l10n-keys.mjs        # المتوقع: 443 مفتاحًا × لغتين، 729 استخدامًا
node tools/check-dart-imports.mjs     # المتوقع: 89 ملفًا بلا استيراد مكسور
```

**إعادة التحقق من نتائج CI من دون تنزيل سجلات:**
```bash
gh api repos/mohamedkamel78/ERP_KAYAN/actions/runs/38363607902/jobs -q '.jobs[] | "\(.name) => \(.conclusion)"'   # Demo backup  (كان failure)
gh api repos/mohamedkamel78/ERP_KAYAN/actions/runs/38363607929/jobs -q '.jobs[] | "\(.name) => \(.conclusion)"'   # Web & Backend CI
gh api repos/mohamedkamel78/ERP_KAYAN/actions/runs/38363607919/jobs -q '.jobs[] | "\(.name) => \(.conclusion)"'   # Windows package
gh api repos/mohamedkamel78/ERP_KAYAN/commits/a04ec42/check-runs -q '.check_runs[] | "\(.name): \(.conclusion)"'
gh run list --branch arena/0b8b25ad-erp-kayan --limit 6
```
**إعادة إثبات الإصلاح (بدل إعادة إثبات العيب):** استدعِ `POST /api/v1/backup/restore?replace=true` بملف `demo-data/kayan-company-backup-demo.json` على تركيب فيه سجلات تدقيق ⇒ المتوقع **HTTP 201** و`total written` بالآلاف، ثم في القاعدة: صف `AUDIT_PURGED` بسبب `company-json-restore` وصف `RESTORE_REPLACE`، والكتب متوازنة (`debits == credits` بفرق `0.0000`).

---

### إقرار الصدق
- في الجولة الأخيرة (الالتزام `a04ec42`) تبيّن أن التعليمات الأخيرة كانت تقول «توثيق وتحقق فقط»، لكن طلبك في الرسالة الأخيرة كان صريحًا: **نفّذ الإصلاحات وأعد الاختبار وأنشئ Setup جديدًا وتقريرًا نهائيًا**. لذلك أُصلح العيبان (لا مجرد توثيقهما)، ونُفِّذت اختبارات جديدة، وأُعيد تشغيل CI كاملًا على رأس الإصلاح.
- لم أُشغّل Flutter ولا Chrome ولا Windows في بيئة التنفيذ هذه؛ ولم أدّعِ اختبار أي واجهة لم تُشغَّل. اختبارات Flutter/المتصفح/الـSetup كلها من GitHub Actions (روابطها في القسمين «ز» و«ط»).
- لم يُمَسّ `main`، ولم يُفتح إصدار جديد، ولم يُعدّل `v1.0.1`، ولم تُمَس أي بيانات مستخدم حقيقية (كل إثباتات التصفير/الاستعادة جرت على قواعد اختبار مؤقتة أنشأتها بنفسي).
- لم أفتح PR ولم أدمج ولم أنشر أي إصدار.
- العيبان الحرجان (استعادة JSON / تصفير الشركة) مُذكَّران هنا بصراحة مع سببهما الجذري وموضعه في الشيفرة، ثم أُصلحا في `a04ec42` وأُثبت الإصلاح باختبارات وبتشغيل CI كامل — ولم أُخفِ أي فشل آخر.
