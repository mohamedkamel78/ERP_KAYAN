#!/usr/bin/env node
/**
 * Drives the real KAYAN ERP web app in a real browser and checks the four
 * things a person does with a file: download an export, print a report,
 * choose a spreadsheet to import, and take a full backup.
 *
 * What it asserts comes from the browser itself, not from pixels: the files
 * that arrive (CDP download events), the tabs that open (their URLs), and the
 * requests the app sends. The screen is only clicked - through Flutter's
 * accessibility labels (`--force-renderer-accessibility`), so the script
 * follows the wording of the buttons rather than their coordinates.
 *
 *   node tools/browser/app_actions_check.mjs [appUrl]
 *
 * Environment:
 *   CHROME_PATH        the browser to drive (default: the usual install paths)
 *   ADMIN_USERNAME     sign-in name   (default: admin)
 *   ADMIN_PASSWORD     sign-in secret (default: Admin@12345 - the dev seed)
 *   OUT_DIR            where screenshots and downloads go (default: /tmp/kayan-e2e)
 *
 * Exit code 0 means every check passed. Each check prints PASS/FAIL with what
 * it saw, so a failure in CI says which promise was broken and how.
 */

const { createRequire } = require('node:module');
const { mkdirSync, writeFileSync, existsSync, readFileSync } = require('node:fs');
const { join, resolve } = require('node:path');
const { spawnSync } = require('node:child_process');

const require2 = createRequire(__filename);
let puppeteer;
try {
  puppeteer = require2('puppeteer-core');
} catch {
  // Installed on demand where the tool runs (CI job or a dev machine).
  spawnSync('npm', ['install', '--no-save', '--prefix', __dirname, 'puppeteer-core'], {
    stdio: 'inherit',
  });
  puppeteer = require2('puppeteer-core');
}

const APP_URL = process.argv[2] || process.env.APP_URL || 'http://127.0.0.1:3000';
const USERNAME = process.env.ADMIN_USERNAME || 'admin';
const PASSWORD = process.env.ADMIN_PASSWORD || 'Admin@12345';
const OUT_DIR = process.env.OUT_DIR || '/tmp/kayan-e2e';

const results = [];
function check(name, ok, detail) {
  results.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` - ${detail}` : ''}`);
}

function chromePath() {
  if (process.env.CHROME_PATH) return process.env.CHROME_PATH;
  const candidates = [
    '/usr/bin/google-chrome',
    '/usr/bin/google-chrome-stable',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  ];
  return candidates.find(existsSync);
}

async function main() {
  mkdirSync(OUT_DIR, { recursive: true });
  const downloadDir = join(OUT_DIR, 'downloads');
  mkdirSync(downloadDir, { recursive: true });

  const browser = await puppeteer.launch({
    executablePath: chromePath(),
    headless: true,
    // The one flag that matters: with it, Flutter web publishes its
    // accessibility tree into the DOM and the buttons can be found by name.
    args: ['--force-renderer-accessibility', '--no-sandbox', '--disable-dev-shm-usage'],
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 900 });

  // Observe downloads through the browser's own download manager.
  const cdp = await page.createCDPSession();
  const downloads = [];
  await cdp.send('Browser.setDownloadBehavior', {
    behavior: 'allowAndName',
    downloadPath: downloadDir,
    eventsEnabled: true,
  });
  cdp.on('Browser.downloadWillBegin', (e) => {
    downloads.push({ url: e.url, suggested: e.suggestedFilename, guid: e.guid, done: false });
  });
  cdp.on('Browser.downloadProgress', (e) => {
    const d = downloads.find((x) => x.guid === e.guid);
    if (d) d.done = e.state === 'completed';
  });

  const network = [];
  page.on('request', (r) => network.push({ url: r.url(), method: r.method(), post: r.postData() }));

  const shot = async (name) => {
    const path = join(OUT_DIR, `${name}.png`);
    await page.screenshot({ path });
    return path;
  };

  /** The centre of the first Flutter semantic node whose name includes [text]. */
  async function findButton(text) {
    return page.evaluate((needle) => {
      const nodes = Array.from(
        document.querySelectorAll('flt-semantics, [role="button"], [role="menuitem"], [role="tab"]'),
      );
      for (const node of nodes) {
        const label = `${node.getAttribute('aria-label') || ''} ${node.textContent || ''}`;
        if (label.trim().toLowerCase().includes(needle.toLowerCase())) {
          const rect = node.getBoundingClientRect();
          if (rect.width > 0 && rect.height > 0) {
            return { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 };
          }
        }
      }
      return null;
    }, text);
  }

  async function clickNamed(text, { timeoutMs = 8000 } = {}) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const at = await findButton(text);
      if (at) {
        await page.mouse.click(at.x, at.y);
        return true;
      }
      await new Promise((r) => setTimeout(r, 250));
    }
    return false;
  }

  async function waitForDownload(previousCount, timeoutMs = 30000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const fresh = downloads.slice(previousCount);
      if (fresh.length && fresh.every((d) => d.done)) return fresh;
      await new Promise((r) => setTimeout(r, 250));
    }
    return downloads.slice(previousCount);
  }

  // ─────────────────────────────────────────────────────────── 1. sign in
  await page.goto(APP_URL, { waitUntil: 'networkidle2', timeout: 90000 });
  await new Promise((r) => setTimeout(r, 6000)); // Flutter's first paint
  await shot('01-login');

  const signedIn = await (async () => {
    // The login fields are text boxes, not buttons; click by geometry of the
    // centred card (centre column) and type.
    const box = await page.evaluate(() => ({ w: innerWidth, h: innerHeight }));
    const cx = box.w / 2;
    await page.mouse.click(cx, box.h * 0.51);
    await page.keyboard.type(USERNAME);
    await page.mouse.click(cx, box.h * 0.59);
    await page.keyboard.type(PASSWORD);
    await shot('02-credentials');
    await page.mouse.click(cx, box.h * 0.68);
    await new Promise((r) => setTimeout(r, 9000));
    await shot('03-after-signin');
    return page.url();
  })();
  check('sign in opens the workspace', !/login|signin|setup/.test(signedIn), `now at ${signedIn}`);

  // ────────────────────────────────────────────── 2. export download
  const before = downloads.length;
  const wentToReports = await clickNamed('التقارير');
  await new Promise((r) => setTimeout(r, 5000));
  await shot('04-reports');
  check('the reports entry opens', wentToReports, `at ${page.url()}`);

  const clickedExcel = await clickNamed('إكسل');
  const arrived = await waitForDownload(before);
  check(
    'an export button downloads a spreadsheet file',
    clickedExcel && arrived.length > 0,
    arrived.map((d) => d.suggested).join(', ') || 'no download arrived',
  );
  if (arrived.length) {
    const path = join(downloadDir, arrived[arrived.length - 1].guid);
    const file = existsSync(path) ? path : join(downloadDir, arrived[arrived.length - 1].suggested);
    const bytes = existsSync(file) ? readFileSync(file) : Buffer.alloc(0);
    check('the downloaded file is a real spreadsheet', bytes.length > 500, `${bytes.length} bytes`);
  }

  // ────────────────────────────────────────────── 3. print page
  const beforeTabs = (await browser.pages()).length;
  const clickedPrint = await clickNamed('طباعة');
  await new Promise((r) => setTimeout(r, 6000));
  const pages = await browser.pages();
  const printPage = pages[pages.length - 1];
  const printUrl = pages.length > beforeTabs ? printPage.url() : page.url();
  check(
    'the print button reaches a print page',
    clickedPrint && /\/print/.test(printUrl),
    printUrl,
  );
  if (pages.length > beforeTabs) {
    await printPage
      .screenshot({ path: join(OUT_DIR, '05-print-page.png') })
      .catch(() => {});
    await printPage.close().catch(() => {});
    await page.bringToFront();
  }

  // ────────────────────────────────────────────── 4. import template + file
  const beforeTemplate = downloads.length;
  const wentToImport = await clickNamed('رفع بيانات');
  await new Promise((r) => setTimeout(r, 5000));
  await shot('06-import');
  check('the import entry opens', wentToImport, `at ${page.url()}`);

  const clickedTemplate = await clickNamed('القالب');
  const templateArrived = await waitForDownload(beforeTemplate);
  check(
    'the template button downloads a file',
    clickedTemplate && templateArrived.length > 0,
    templateArrived.map((d) => d.suggested).join(', ') || 'no download arrived',
  );

  // Choosing a file: the real system dialogue is driven through CDP.
  const dryRunMark = network.length;
  let choseFile = false;
  try {
    const [chooser] = await Promise.all([
      page.waitForFileChooser({ timeout: 8000 }),
      clickNamed('اختر'),
    ]);
    // Any small spreadsheet the server can parse; the fixture is written here
    // so the tool travels alone.
    const fixture = join(OUT_DIR, 'import-fixture.csv');
    writeFileSync(fixture, 'code,name_ar,name_en\nE2E-1,اختبار,Check\n');
    await chooser.accept([fixture]);
    choseFile = true;
  } catch {
    choseFile = false;
  }
  await new Promise((r) => setTimeout(r, 7000));
  await shot('07-after-file');
  const dryRunCalls = network
    .slice(dryRunMark)
    .filter((r) => /import\/.*dry/i.test(r.url) || (/import\//.test(r.url) && r.method === 'POST'));
  check(
    'choosing a file makes the app read it on the server',
    choseFile && dryRunCalls.length > 0,
    choseFile ? `${dryRunCalls.length} read request(s)` : 'no file chooser opened',
  );

  // Closing the dialogue without a file must not wedge the button.
  let cancelRecovered = false;
  try {
    const [chooser] = await Promise.all([
      page.waitForFileChooser({ timeout: 8000 }),
      clickNamed('اختر'),
    ]);
    await chooser.dismiss();
    await new Promise((r) => setTimeout(r, 1500));
    const [chooser2] = await Promise.all([
      page.waitForFileChooser({ timeout: 8000 }),
      clickNamed('اختر'),
    ]);
    await chooser2.dismiss();
    cancelRecovered = true;
  } catch {
    cancelRecovered = false;
  }
  check('closing the file dialogue twice in a row is fine', cancelRecovered);

  // ────────────────────────────────────────────── 5. full backup
  const beforeBackup = network.length;
  const beforeDump = downloads.length;
  const wentToBackup = await clickNamed('النسخ الاحتياطي');
  await new Promise((r) => setTimeout(r, 5000));
  await shot('08-backup');
  check('the backup entry opens', wentToBackup, `at ${page.url()}`);

  const clickedCreate = await clickNamed('إنشاء نسخة');
  await new Promise((r) => setTimeout(r, 20000));
  await shot('09-backup-made');
  const backupCalls = network
    .slice(beforeBackup)
    .filter((r) => /backup\/full/.test(r.url) && r.method === 'POST');
  check(
    'the backup button asks the server for a full backup',
    clickedCreate && backupCalls.length > 0,
    `${backupCalls.length} backup request(s)`,
  );

  const clickedDump = await clickNamed('تنزيل');
  const dumpArrived = await waitForDownload(beforeDump);
  check(
    'the backup file downloads',
    clickedDump && dumpArrived.length > 0,
    dumpArrived.map((d) => d.suggested).join(', ') || 'no download arrived',
  );
  if (dumpArrived.length) {
    const file = join(downloadDir, dumpArrived[dumpArrived.length - 1].guid);
    const alt = join(downloadDir, dumpArrived[dumpArrived.length - 1].suggested);
    const path = existsSync(file) ? file : alt;
    const bytes = existsSync(path) ? readFileSync(path) : Buffer.alloc(0);
    const magic = bytes.subarray(0, 5).toString('latin1');
    check('the backup is a PostgreSQL archive', magic === 'PGDMP', `magic=${JSON.stringify(magic)}`);
  }

  // ─────────────────────────────────────────────────────────── summary
  await shot('10-final');
  const failures = results.filter((r) => !r.ok);
  console.log(
    `\n${results.length - failures.length}/${results.length} checks passed` +
      (failures.length ? ` - FAILED: ${failures.map((f) => f.name).join('; ')}` : ''),
  );
  await browser.close();
  process.exit(failures.length ? 1 : 0);
}

main().catch((error) => {
  console.error('the browser check itself broke:', error);
  process.exit(2);
});
