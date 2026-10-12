# فحص الواجهة في متصفح حقيقي

الأدوات اللي في المجلد ده بتشغّل البرنامج في متصفح (Chromium) وتتكلم معاه
مباشرة، عشان تتأكد إن الحاجة اللي المستخدم بيشوفها شغالة — مش بس إن السيرفر
بيرد صح.

## التشغيل

متصفح شغال في الخلفية مع منفذ التحكم:

```bash
chromium --headless=new --no-sandbox --disable-gpu \
         --remote-debugging-port=9222 --remote-allow-origins=* \
         --window-size=1440,900 about:blank
```

وبعدين (لازم `pip install websocket-client`):

```bash
python3 tools/browser/browser_check.py http://localhost:3000
python3 tools/browser/browser_login_shots.py http://localhost:3000
python3 tools/browser/browser_download_check.py http://localhost:3000
```

**`browser_check.py`** — الصفحة تفتح، الواجهة اتحمّلت، مفيش أخطاء في console،
والشاشات الجديدة بترسم.

**`browser_login_shots.py`** — بيسجّل الدخول بالماوس وبيدوس على بنود القائمة
وبيصوّر كل شاشة في `/tmp/out/`.

**`browser_download_check.py`** — بيدوس على أزرار Excel و CSV و طباعة، ويراقب
الطلب اللي المتصفح بعته والملف اللي رجع، وبيقيس محتواه (ملف Excel حقيقي،
وملف CSV فيه علامة BOM للعربي، وصفحة طباعة فيها أرقام التقرير).

> ملاحظة: المتصفح المجرد (headless) بيلغي التنزيل بعد ما يبدأ، عشان كده
> السكربت بيتأكد من الطلب والمحتوى، مش من ملف على القرص.


---

## `app_actions_check.mjs` — الفحص اللي بيشغّله CI

ده الأدوات اللي بتتكلم مع البرنامج **بالأسماء** مش بالإحداثيات: بيفتح Chrome
المجرد، بيدوّر على زرار اسمه «تسجيل الدخول» أو «Login» من شجرة الـaccessibility
بتاعة Flutter، بيدوس، وبعدين بيقيس الحاجة اللي المفروض تحصل — مش صورة
الشاشة.

```bash
# سيرفر شغال على 3000 وقاعدة بيانات فيها seed
node tools/browser/app_actions_check.mjs http://127.0.0.1:3000
```

`puppeteer-core` بيتنصّب لوحده لو مش موجود (`npm install --no-save --prefix
tools/browser puppeteer-core`). المتصفح بيلاقي نفسه من `CHROME_PATH` أو من
المسارات المعروفة؛ `--force-renderer-accessibility` مضمّن، ومعاه
`?a11y=1` في العنوان بيفعّل شجرة الأسماء من جوه التطبيق (`main.dart`).

**بيفحص إيه:** إن الأسماء بتنزل من التطبيق · إن الدخول يفتح مساحة العمل · إن
زرار Excel ينزّل ملف Excel حقيقي · إن الطباعة تفتح صفحة طباعة · إن تنزيل
القالب يشتغل · إن اختيار ملف من الزرار يخلّي السيرفر يقراه، وإن إلغاء
الحوار مرتين مبوظش الزرار · إن زرار النسخ الاحتياطي يعمل نسخة ويتنزّل ملف
`PGDMP` · إن الصفحة مفيهاش أخطاء console ولا أي 5xx من السيرفر.

**مخرجاته** (في `OUT_DIR`، افتراضياً `/tmp/kayan-e2e`): `summary.txt` و
`browser-check.json` وصور `*.png` و`labels-*.json` و`inputs-*.json` لكل خطوة
فشل فيها دوسة — لأن الدوسة اللي ملقتش حاجة هي غالباً تغيير نص، والنص الحقيقي
لازم يتقري مش يتخمن. وفي GitHub كمان: كل طلب `/api/v1` اتردّ عليه بـ4xx بينزل
كسطر `HTTP <status> <method> <path>`، وكل ملف رجع بينزل كسطر `FILE`، والملخص
بالأرقام بيتكتب في `GITHUB_STEP_SUMMARY` وكملاحظة على صفحة الـrun — لأن
GitHub بيحتفظ بعشر ملاحظات بس وبيأخد أولهم، والتشخيص الدائم يكون في الآخر.
