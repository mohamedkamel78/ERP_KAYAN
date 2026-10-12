# جرد المتطلبات — Requirements Audit

آخر تحديث: 2026-10-12 (جلسة «تكملة CI والنسخ الاحتياطي والبيانات التجريبية» —
الفرع `arena/43cdf143-erp-kayan`، وهو `arena/279eb1f7-erp-kayan` زائد أعمال هذه
الجلسة؛ لا شيء من العمل السابق حُذف). الحالة من أربعة قيم:
✅ منفذ ومختبَر فعلياً · 🟡 منفذ جزئياً · 🔵 موجود لكن غير مختبَر · ❌ غير منفذ.
كل اختبار مذكور هنا **شُغّل فعلاً**؛ وما لم يُشغَّل مكتوب صراحةً مع السبب.

## الجولة الحالية (2026-10-12) — المطلوب من المستخدم، بنداً بنداً

| # | البند | الحالة | الإثبات (تشغيل فعلي، لا وصف كود) |
|---|---|---|---|
| 1 | تذاكر تنزيل قصيرة العمرة وكل مواضع استخدامها | ✅ | `api-check.mjs` §4b و§4d: تذاكر بصلاحية دقيقة، الـaccess token مرفوض في العنوان (401)، التذكرة لا تُقبل كـBearer، و**مسح لكل عنوان تضعه الأزرار** (`/exports/**`, `/import/templates/**`) بثلاثين+ مساراً: كلها 200 بالتذكرة وحدها وبلا هيدر، والمفتاح مقفول بدونها. CI job *API checks against a real database* أخضر. |
| 2 | إعادة ضبط البيانات للمدير فقط، بكلمة سر وتأكيد ونسخة موثَّقة | ✅ | `reset.service.spec.ts` (13 حالة: كلمة سر خاطئة 401، تأكيد ناقص 400، كلمة السر لا تظهر في السجل) + `api-check.mjs` §7 على PostgreSQL حقيقية: معاينة العدّادات، رفض كلمة السر الخاطئة، رفض `reset` بدل `RESET`، `reset:true` مع ملف نسخة حقيقي، مسح بيانات الشركة، والسجل فيه `RESET` بلا كلمة السر. |
| 3 | ملف نسخة تجريبية واحد بحقيقي بالصيغة المدعومة، مُستعاد فعلياً | ✅ | workflow *Demo backup file*: `npm run build:demo` يبني `kayan-demo-backup-<date>.dump` (PGDMP custom) من مسار البرنامج نفسه، يستعيده في قاعدة مؤقتة ويتأكد من الأرقام بعده، ثم يحطّه في قاعدة ثالثة فارغة لإثبات أنه يحمل بنيته. الـartifact `kayan-demo-backup` منشور مع SHA256، والنتيجة (N/M checks passed) بقت تُنشر كـnotice على صفحة الـrun. |
| 4 | إنشاء/اختيار/رفع/تنزيل/تحقق/استعادة | ✅ للأجزاء الخلفية | `api-check.mjs` §3–§6: إنشاء، ظهور الملف في القائمة، تنزيل بميلغ attach، رفض ملف ليس dump (400) دون لمس البيانات، رفض الاستعادة بلا confirm، استعادة مع rehearsal في قاعدة مؤقتة + نسخة أمان + تحقق، والبرنامج يرد بعدها. `full-backup.service.spec.ts` (4 حالات). |
| 5 | الطباعة والتنزيلات في كل البرنامج | 🟡 | سيرفرًا: صفحات الطباعة HTML/RTL وxlsx/csv تُنزَّل بالتذكرة (فوق). في متصفح حقيقي: `tools/browser/app_actions_check.mjs` — التنزيل من شاشة النسخ الاحتياطي والـPGDMP ✓، وباقي الأزرار (Excel/طباعة/قالب) لا تزال تُرفض بثلاثة 401، يجري تحديد عنوانها بالضبط (التشغيل فيه `HTTP <status> <method> <path>` لكل طلب مرفوض). |
| 6 | تدفق الاستيراد الكامل وdry-run آمن | ✅ | `import.service.spec.ts` (4) + `api-check.mjs` §6: تنزيل القالب، إرجاعه كما هو يُقبل (`created:1, errors:0`)، صف ناقص يُسمّى بالعمود والسطر، وdry-run لا يكتب شيئاً (0 عميل بعدها). في الـFlutter test: `import_controller_test.dart` (جاف/ترجمة/تغيير الملف). |
| 7 | خطأ Financial Periods `AuthFailure: Invalid or expired token` | ✅ | السبب: العميل كان يخزّن refresh token ولا يستخدمه. `api_client.dart` يجدّد مرة واحدة عند 401 ويعيد الطلب، والتجديدات المتزامنة تتشارك محاولة واحدة، ولو تعذّر التجديد يسجّل الخروج. `api-check.mjs` §4c يفحصه سيرفرًا: تجديد بـrefresh صالح، الرمز المجدد يفتح `/accounting/fiscal-periods`، إعادة استخدام refresh مرفوضة، ورمز مخترع يرد بجملة لا بانهيار. وفي هذه الجلسة وُجد سببان آخران لنفس العرض وأُصلحا: `restoreSession()` كان **يمسح** الرمز عند أي فشل (حتى انقطاع شبكة) فطرد المستخدم من كل نوافذ المتصفح — صار المسح فقط إذا قال السيرفر إن الرمز نفسه فاسد (`test/auth/auth_repository_restore_test.dart`)؛ و`POST /auth/logout` كان يرد 401 عند خروج بلا رمز، فكرر العميل تسجيل الخروج 2999 مرة في دقيقة حتى استنفد حد معدل العنوان (وهو ما كان يجعل كل التنزيلات تُرفض) — صار `@OptionalAuth()` وحلقة اختبار في `test/core/api_client_session_test.dart`. |
| 8 | إصلاحات Flutter وanalyze وtests وbuild الويب | ✅ | CI job *Flutter Web Build*: `node tools/check-dart-imports.mjs` (كل الـimports تشير لملفات موجودة)، `flutter analyze` نظيف، `flutter test` أخضر، و`flutter build web --release` ينجح ويُنشر كـartifact `KAYAN-ERP-web`. |
| 9 | اختبارات Backend وقاعدة بيانات وAPI وE2E في متصفح حقيقي | ✅ للسيرفر، 🟡 للمتصفح | Backend: 14 suite / **127** اختبار jest خضراء محلياً وفي CI (منها 4 جديدة لـ`@OptionalAuth`)، و`tsc --noEmit` و`nest build` نظيفان. API/DB: job *API checks against a real database* — **58 فحصاً نجحت** على PostgreSQL 16 حقيقية مع migrations وseed وبناء حقيقي. المتصفح: job *Browser checks* — **14/17** على التشغيل 38219578855؛ ما بقي بندان على شاشة الاستيراد (زر القالب وإغلاق حوار الملف مرتين) وسطر 401 واحد في اللوج، والتشخيص مكتوب في سطر 5. |
| 10 | حزمة Windows: ZIP وinstaller | 🔵 | السكربتات موجودة و`verify-package.ps1` وworkflow *Windows package* يعملان على `pull_request`؛ آخر تشغيل كامل نجح كان على رأس PR #3، وتشغيل PR #4 أُلغي يدوياً (`The run was canceled by @mohamedkamel78`) قبل أن يكتمل. شُغِّل على PR #5 لهذا الفرع (التشغيل 38219584564، `windows-latest`) — نتيجته وروابط `KAYAN-ERP-windows.zip` و`KAYAN-ERP-Setup-*.exe` تُذكر هنا فور اكتماله؛ لن يُدمج أي PR بأمرك. |
| 11 | وصول آمن من أجهزة الشبكة وتحضير HTTPS | ✅ للتحضير | `network.ts` + 14 حالة اختبار: `TRUST_PROXY` (loopback/true/عدد الوسائط)، `KAYAN_REQUIRE_HTTPS` (308 لا يشمل `/api/v1/health`)، HSTS على TLS فقط، ورفض قيمة غير مفهومة مع رسالة في اللوج. الهيدرز الأربعة على كل رد (API والواجهة) مفحوصة في `api-check.mjs` على سيرفر حقيقي. `docs/NETWORK_ACCESS.md` + `scripts/lan-access.ps1` + `deploy/Caddyfile.example` + `deploy/kayan.nginx.conf.example`. |
| 12 | الحفاظ على كل ما سبق | ✅ | الفرق بين `origin/main` وهذا الفرع: ~9.4 ألف سطر إضافة في 75+ ملفاً، بلا حذف أي ميزة؛ `git merge-base` يؤكد أن رأس PR #4 داخل هذا الفرع، وأعمال PR #3 كلها أجدّ منها نسخة مكتملة هنا. |

**ما لم يُشغَّل في هذه البيئة ولماذا:** لا Flutter SDK ولا Chrome ولا PostgreSQL في
sandbox المطوّر، لذلك `flutter analyze/test/build web` وفحص المتصفح وتشغيل الـAPI
حياً — كلها تتشغّل على الـrunner وتُقرأ نتائجها من الـrun (روابط في التقرير)،
لا من وصفي أنا. وحزم Windows تُبنى على `windows-latest` فقط.

---

## 1. إعداد الشركة

| البند | الحالة | الإثبات | الاختبار |
|---|---|---|---|
| اسم عربي/إنجليزي + كود + بيانات اتصال في الإعداد الأول | ✅ | `backend/src/modules/company/dto/company.dto.ts` (`InitialSetupDto`)، `lib/shared/widgets/company_setup_form.dart`، `login_screen.dart` (ويب)، `backend_gate.dart` (سطح المكتب) | اختبار حي على `kayan_test` فارغة: `POST /setup/initial` → 201 ثم `GET /company/profile` أرجع الاسمَين والهاتف |
| مقر رئيسي vs فرع + ربط الفرع بالأب | ✅ | `setup.service.ts` (يُنشئ المقر بـ`hqCode/hqName*` و`kind: HEADQUARTERS`)، `company.service.ts` (فروع مع `kind`/`parentBranchId` + فحص الدوران)، شاشة «بيانات الشركة» | حي: المقر `CAIRO` أُنشئ بنوع HEADQUARTERS واسمه العربي؛ إنشاء فرع مرتبط + رفض مقر ثانٍ (409) في جلسة سابقة |
| شعار اختياري في الإعداد | ✅ | `InitialSetupDto.logoBase64/logoMime` (تحقّق magic + 2MB)، ومسار سطح المكتب عبر `KAYAN_COMPANY_LOGO_FILE` (seed.ts الجديد) | حي: شعار base64 في setup/initial → `hasLogo: true`؛ وseed مع ملف Kayan.png → 55,995 بايت مخزّنة بـ`image/png` |
| الحفظ في القاعدة والاستخدام في البرنامج والتقارير | ✅ | `companies` (logoData BYTEA)، `export.controller.ts` `companyHeader()` في كل ملفات التصدير | حي: xlsx يحوي اسم الشركة والشعار مضمّناً (xl/media) |
| التحقق من الصحة والصلاحيات | ✅ | `class-validator` على DTO + `admin.company.manage` على مسارات التعديل | حي: payload ناقص → 400؛ مستخدم بلا الصلاحية → 403 |
| استكمال الإعداد إذا توقف المستخدم | ✅ | نموذج الإعداد يحفظ مسودة محلية (بلا كلمات مرور) ويستعيدها؛ الخادم transactional ويقبل إعادة المحاولة ويرفض التكرار | حي: استدعاء ثانٍ لـ`/setup/initial` → 409 «already set up» (بلا تكرار)؛ ميزة المسودة في الكود (تُختبر محلياً بـ flutter test) |

## 2. شاشة تسجيل الدخول (تذكرني)

| البند | الحالة | الإثبات | الاختبار |
|---|---|---|---|
| حفظ اسم المستخدم (وكلمة المرور حيث التخزين الآمن متاح) | ✅ | `lib/core/storage/credentials_store.dart` + `login_screen.dart` (checkbox متوقف افتراضياً + زر مسح) | `flutter test`: حالات `credentials_store_test.dart` الست نجحت |
| لا نص صريح لكلمة المرور في تخزين غير آمن | ✅ | كلمة المرور في `FlutterSecureStorage` فقط؛ الويب لا يحفظها إطلاقاً؛ مسودة الإعداد تستثنيها | فحص الكود + الاختبارات أعلاه تفحص `prefs.getString('login.password') == null` |
| لا كشف في السجلات | ✅ | `local_backend_io.dart` يبدّل `KAYAN_ADMIN_PASSWORD=***` قبل كتابة اللوج؛ سجلات الـAPI لا تطبع كلمات مرور | فحص الكود (بدون أسرار في diff — انظر التقرير) |
| آلية المصادقة الفعلية | ✅ | JWT (access/refresh) في تخزين آمن؛ الرموز تُخزَّن hashed في `refresh_tokens`؛ لا تغيير في نظام المصادقة | حي: login/refresh عبر API في هذه الجلسة |

## 3. دليل الحسابات

| البند | الحالة | الإثبات | الاختبار |
|---|---|---|---|
| مستويات فرعية متعددة دون حد ثابت | ✅ | `chart-of-accounts.service.ts` (شجرة `parentId` ذاتية، DFS في التصدير) | حي: 30 حساباً بثلاثة مستويات (1→11→1101) |
| كود فريد + ربط أب/ابن صحيح | ✅ | قيد فريد (companyId+code)، تغيير الكود ممنوع بعد الحركات | حي: كود مكرر → 409؛ `suggest-code` = 1106 تحت 11 |
| نوع الحساب + تجميعي vs نهائي | ✅ | `type` + `isPostable`؛ تحويل الأب لتجميعي تلقائياً؛ رفض ترحيل للتجميعي | حي/اختبارات jest: منع الترحيل للحساب التجميعي «Accounts cannot receive postings»؛ jest: ترقية الأب التلقائية |
| بحث وتصفية وإضافة وتعديل + صلاحيات | ✅ | REST كامل (`accounting.accounts.*`)، شاشة شجرة بفلاتر | حي: 403 بدون الصلاحية؛ jest 12 اختبار قواعد |
| منع حذف الحساب بحركات + أرشفة آمنة | ✅ | الحذف مرفوض مع حركات أو أبناء مع اقتراح التعطيل (`isActive` = الأرشفة الآمنة) | jest: رفض حذف بحركات/أبناء، نجاح حذف ورقي |
| صحة التقارير والأرصدة بعد المستويات | ✅ | ميزان المراجعة/دفتر الأستاذ يجمّعان من السطور؛ التصدير بترتيب الشجرة | حي: xlsx ميزان المراجعة يشمل الشجرة والمستويات |

## 4. اللغة العربية والإنجليزية

| البند | الحالة | الإثبات | الاختبار |
|---|---|---|---|
| واجهات وبيانات وتقارير باللغتين | ✅ | `app_ar.arb`/`app_en.arb` (379 مفتاحاً)، `accountName()` مركزي للبيانات | حي: قيد بأسماء عربية في السطور؛ xlsx عربي |
| RTL للعربية / LTR للإنجليزية | ✅ | `Directionality` من locale؛ print HTML `dir="rtl"/"ltr"` | حي: HTML الطباعة `lang="ar" dir="rtl"` |
| بحث بالاسمين والكود + لا نصوص غير مترجمة | ✅ | فلتر البحث يقرأ nameAr/nameEn/code؛ فحص اتساق ARB↔المولّد نظيف (379/379) | `flutter analyze` بلا ملاحظات؛ اختبارات Flutter شملت RTL والعربية |
| آلية ترجمة مركزية + معالجة الناقص | ✅ | `account-name.ts` / `account_name.dart` (المفضّل ← الآخر ← الكود، أبداً فارغ) | Jest وFlutter tests نجحت |

## 5. تصدير Excel وPDF

| البند | الحالة | الإثبات | الاختبار |
|---|---|---|---|
| بيانات فعلية وفق الفلاتر | ✅ | `list-tables.service.ts` يطبّق `q/status/from/to/includeInactive` من الاستعلام | حي: تصدير القيود يعكس البيانات الحقيقية |
| Excel احترافي بأنواع صحيحة | ✅ | `writers.spec.ts` يتحقق: خلايا رقمية/تاريخية حقيقية، RTL، عروض أعمدة، إجماليات | jest + حي (PK zip، 65KB مع الشعار) |
| PDF عربي + بيانات الشركة والشعار | ✅ | print HTML بخطوط عربية + `stampPageNumbers` (pdf-lib) + ترويسة بشعار base64 | jest على HTML؛ **PDF نفسه غير مُختبَر** (لا Chrome في البيئة — `pdfOnTheServer:false` يُخفي الزر بصدق) |
| رؤوس صفحات/ترقيم/أخطاء | ✅ | `thead` مكرر، `.print-foot`، أرقام صفحات، أخطاء Problem Details | jest (writers) |
| التنزيل في المتصفح وWindows | 🟡 | `browser_actions` (openInNewTab) + AllowQueryToken على روابط الملفات | مسار المتصفح مُشغَّل حياً عبر curl؛ **تجربة النقر الفعلية في متصفح/ويندوز لم تُجرَ** |

## 6. قاعدة البيانات وسلامة البيانات

| البند | الحالة | الإثبات | الاختبار |
|---|---|---|---|
| فحص المخطط والـmigrations قبل التعديل | ✅ | 6 migrations تجميعية فقط (لا DROP) | مُطبَّقة على `kayan` و`kayan_test` بنجاح |
| حفظ البيانات + منع reset/drop | ✅ | لا `migrate reset` ولا `db push` ولا حذف جداول في أي مسار | فحص diff كامل |
| لا تغيير كلمات مرور PostgreSQL / pg_hba | ✅ | لا يوجد أي كود يلمسهما | فحص diff |
| migrations آمنة للبيانات الحالية | ✅ | `20261011160000_grant_new_permissions` idempotent (ON CONFLICT DO NOTHING) | حي: إعادة التشغيل تُدرج صفراً؛ محاكاة قاعدة قديمة → المنح تعود بالسياسة الصحيحة |
| اختبارات API/صلاحيات/تصدير | ✅ | 47 jest + فحوصات API حية هذه الجلسة | `npx jest` = 47/47 |

## 7. التشغيل والبناء

| البند | الحالة | الإثبات | الاختبار |
|---|---|---|---|
| الواجهة والـBackend والاتصال بقاعدة البيانات | ✅ | API كامل يعمل على PG 16.2 حقيقية | حي: health/login/COA/journal/exports/backup كلها 2xx |
| بناء نسخة الويب | ✅ | Flutter Web Release | `flutter build web --release` اكتمل؛ تحذير غير مانع بشأن خط CupertinoIcons |
| توافق Windows | ✅ | Windows x64 + Visual Studio؛ 38 ملفاً تنفيذياً أصلياً داخل الحزمة | `scripts\build-desktop-windows.ps1` بنجاح؛ بُني `erp_kayan.exe` |
| تجهيزات Setup ومحتوياته | 🟡 | بُني `build\desktop\KAYAN-ERP-Setup-1.0.0.exe` بحجم 112,008,392 بايت (106.82 MiB)؛ الحزمة تتضمن التطبيق وNode.js وpg_dump/pg_restore | ISCC: Successful compile؛ `verify-package.ps1`: 40 فحصاً ناجحاً. هذا ليس Setup مستقلاً: لا يضمّن PostgreSQL Server أو خدمة KAYAN؛ يتطلب PostgreSQL خارجية، ولم يُختبر تثبيت/تشغيل/إزالة على جهاز نظيف |
| لا تغيير بنية أو حذف ضروري | ✅ | الحفاظ على كل الملفات؛ الدمج مع main حافظ على جانبيه | git log/diff |

---

## نتائج التشغيل الفعلية (2026-10-11)

- `npx tsc --noEmit` → نظيف
- `npm run build` → ناجح؛ `npx jest --runInBand` → **47/47** (6 مجموعات)
- `flutter analyze` → بلا ملاحظات؛ `flutter test` → **89 اختباراً ناجحاً**؛ حالتا اختبار رفع الملفات الحيتان تخطّتا عدم وجود API يعمل على المنفذ 3000
- `dart run tools/backend_shape_check.dart` → **16/16**
- `flutter build web --release` → ناجح
- `scripts/build-desktop-windows.ps1` → بناء Windows x64 وملف Setup اكتمل؛ `verify-package.ps1` → **40/40**
- API حي على PostgreSQL 16.2: تسجيل دخول، setup/status، company profile+logo، شجرة 30 حساباً، كود مكرر 409، اقتراح كود، قيد عربي بأسماء عربية، xlsx (PK/65KB/شعار)، نسخة كاملة 137KB، capabilities (server 16.2 بلا تحذير)
- **تدفق الإعداد الأول كاملاً** على `kayan_test` فارغة: needsSetup:true → setup/initial (اسم عربي/إنجليزي/كود/اتصال/مقر CAIRO/شعار) → needsSetup:false → دخول المدير الجديد → الملف والمقر والشعار والدليل (30 حساباً) → استدعاء ثانٍ مرفوض 409 → payload ناقص مرفوض 400
- فحص علامات التعارض: صفر · فحص الأسرار: صفر أسرار حقيقية

## غير مُنفَّذ/غير مُختبَر — والسبب

1. اختبار PDF المرئي/إنشاء PDF فعلي والتنزيل في متصفح أو Windows — لم يُنفّذ في هذه الجولة.
2. لا يحتوي Setup الحالي PostgreSQL Server ولا ينشئ خدمة/مجلد بيانات KAYAN مستقلاً؛ يعتمد على PostgreSQL موجودة مسبقاً على `127.0.0.1:5432`. لذلك لا يحقق بعد شرط التثبيت المستقل على جهاز Windows نظيف، ولا يُعد إصداراً نهائياً لهذا الهدف.
3. لم يُختبر تثبيت Inno Setup أو تشغيل التطبيق أو إزالته على جهاز نظيف؛ جلسة التنفيذ غير مرتفعة الصلاحية، وتشغيل التطبيق على قاعدة 5432 الموجودة قد يغيّر بياناتها، لذلك لم يُشغّل.
4. نصّ `scripts/install-postgres-portable.bat` الحالي يحذف مجلدات PostgreSQL/PGDATA الموجودة ويهيّئ المصادقة بـ`trust`؛ لم يُشغّل ولم يُستخدم لإعداد قاعدة البيانات.
