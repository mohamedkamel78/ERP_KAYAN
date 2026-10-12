#!/usr/bin/env node
/**
 * Drives the real KAYAN ERP web app in a real browser and checks the four
 * things a person does with a file: download an export, print a report,
 * choose a spreadsheet to import, and take a full backup.
 *
 * What it asserts comes from the browser itself, not from pixels: the files
 * that arrive (CDP download events), the tabs that open (their URLs), and the
 * requests the app sends. The screen is only clicked — through Flutter's
 * accessibility labels (`--force-renderer-accessibility`), so the script
 * follows the wording of the buttons rather than their coordinates.
 *
 *   node tools/browser/app_actions_check.mjs [appUrl]
 *
 * Environment:
 *   CHROME_PATH        the browser to drive (default: the usual install paths)
 *   ADMIN_USERNAME     sign-in name   (default: admin)
 *   ADMIN_PASSWORD     sign-in secret (default: Admin@12345 - the dev seed)
 *   OUT_DIR            where screenshots, downloads and the report go
 *                      (default: /tmp/kayan-e2e)
 *
 * Exit code 0 means every check passed. Each check prints PASS/FAIL with what
 * it saw, so a failure in CI says which promise was broken and how.
 *
 * When a button cannot be found, the script writes down every label the page
 * did publish — `labels-*.json` next to the screenshots — because a click
 * that finds nothing is almost always a wording change, and the fix is to
 * read the real wording rather than to guess at it.
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync, writeSync } from 'node:fs';
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const requireFromHere = createRequire(import.meta.url);

const APP_URL = process.argv[2] || process.env.APP_URL || 'http://127.0.0.1:3000';
const USERNAME = process.env.ADMIN_USERNAME || 'admin';
const PASSWORD = process.env.ADMIN_PASSWORD || 'Admin@12345';
const OUT_DIR = process.env.OUT_DIR || '/tmp/kayan-e2e';

// ─────────────────────────────────────────────────────────────── the results

const results = [];
const consoleLines = [];

/**
 * Writes a line to the log, and does not lose it.
 *
 * `console.log` to a pipe is asynchronous in Node: when a process ends with
 * `process.exit()`, whatever it had not flushed yet simply disappears. That
 * is how a run can end with no verdict at the bottom of its own log - the
 * lines were written, they were just not on their way out yet. Writing
 * synchronously means the last line of a failing run is the one that says
 * why.
 */
const log = (line) => {
  consoleLines.push(String(line));
  try {
    writeSync(1, `${line}\n`);
  } catch {
    // stdout is gone (the pipe closed); there is nowhere left to say it.
  }
};

function check(name, ok, detail) {
  results.push({ name, ok, detail: detail ?? null });
  log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` - ${detail}` : ''}`);
  save();
}

function save() {
  try {
    writeFileSync(
      join(OUT_DIR, 'browser-check.json'),
      JSON.stringify(
        { appUrl: APP_URL, ok: results.every((r) => r.ok), results, consoleLines },
        null,
        2,
      ),
    );
    const passed = results.filter((r) => r.ok).length;
    writeFileSync(
      join(OUT_DIR, 'summary.txt'),
      `${passed}/${results.length} checks passed\n` +
        results
          .map((r) => `${r.ok ? 'PASS' : 'FAIL'}  ${r.name}${r.detail ? ` - ${r.detail}` : ''}`)
          .join('\n') +
        '\n',
    );
  } catch {
    /* the report is a courtesy; never let it mask the real failure */
  }
  writeJobSummary();
}

/**
 * The same verdict, written where GitHub shows it without a download.
 *
 * A failing run keeps what it saw in an artifact, and an artifact is only
 * read by someone who already knows they need it. The job summary of a pull
 * request is read by everyone: it sits on the run page. So the verdict, the
 * lines that failed and the last words the page said about itself are written
 * there as well, between a marker so a rerun replaces the block instead of
 * stacking another copy under it.
 */
const SUMMARY_MARKER = '<!-- kayan-browser-checks -->';

function writeJobSummary() {
  const file = process.env.GITHUB_STEP_SUMMARY;
  if (!file) return;
  try {
    const passed = results.filter((r) => r.ok).length;
    const failures = results.filter((r) => !r.ok);
    const seen = consoleLines
      .filter((line) => /^(NAV|HTTP|FILE|TRAFFIC|LABELS missed|CLICK|LOGIN|INPUTS typed|SERVER|DOWNLOAD|pageerror|console)/.test(line))
      .slice(-18);
    const block = [
      SUMMARY_MARKER,
      '### Browser checks',
      '',
      `**${passed}/${results.length} checks passed**`,
      '',
      ...results.map(
        (result) =>
          `- ${result.ok ? 'pass' : '**FAIL**'}  ${result.name}` +
          (result.detail ? ` — ${result.detail}` : ''),
      ),
      failures.length ? '' : null,
      failures.length ? '<details><summary>what the page said while it ran</summary>' : null,
      failures.length ? '' : null,
      failures.length ? '```' : null,
      ...seen.map((line) => line.replace(/\|/g, '¦').slice(0, 240)),
      failures.length ? '```' : null,
      failures.length ? '</details>' : null,
    ].filter((line) => line !== null);

    // Everything before the marker belongs to somebody else's step and stays.
    let before = '';
    if (existsSync(file)) {
      const whole = readFileSync(file, 'utf8');
      const at = whole.indexOf(SUMMARY_MARKER);
      before = at === -1 ? whole : whole.slice(0, at);
    }
    writeFileSync(file, `${before}${block.join('\n')}\n`);
  } catch {
    /* the summary is a courtesy too; a broken one must not fail the check */
  }
}

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// ───────────────────────────────────────────────────────────────── the browser

function chromePath() {
  if (process.env.CHROME_PATH) return process.env.CHROME_PATH;
  return [
    '/usr/bin/google-chrome',
    '/usr/bin/google-chrome-stable',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  ].find(existsSync);
}

function loadPuppeteer() {
  try {
    return requireFromHere('puppeteer-core');
  } catch {
    // Installed on demand where the tool runs (CI job or a dev machine).
    const install = spawnSync(
      'npm',
      ['install', '--no-save', '--prefix', here, 'puppeteer-core'],
      { stdio: 'inherit' },
    );
    if (install.status !== 0) {
      throw new Error('puppeteer-core could not be installed — see the npm output above');
    }
    return requireFromHere('puppeteer-core');
  }
}

async function main() {
  mkdirSync(OUT_DIR, { recursive: true });
  const downloadDir = join(OUT_DIR, 'downloads');
  mkdirSync(downloadDir, { recursive: true });

  const executablePath = chromePath();
  if (!executablePath) {
    check(
      'a browser is installed for the check to drive',
      false,
      'no Chrome or Chromium was found; set CHROME_PATH to one',
    );
    return 1;
  }

  const puppeteer = loadPuppeteer();
  const browser = await puppeteer.launch({
    executablePath,
    headless: true,
    args: [
      // The one flag that matters: with it, Flutter web publishes its
      // accessibility tree into the DOM and the buttons can be found by
      // name rather than by pixel.
      '--force-renderer-accessibility',
      '--no-sandbox',
      '--disable-dev-shm-usage',
      // The program is Arabic-first. Asking the browser for Arabic means
      // what is clicked is what a user in Cairo would read, which is also
      // the harder of the two cases: RTL layout and Arabic filenames.
      '--lang=ar-EG',
      '--accept-lang=ar-EG,ar',
    ],
  });

  try {
    const page = await browser.newPage();
    page.setDefaultTimeout(45000);
    await page.setViewport({ width: 1440, height: 900 });
    await page.setExtraHTTPHeaders({ 'Accept-Language': 'ar-EG,ar;q=0.9' });

    const consoleErrors = [];
    page.on('pageerror', (error) => {
      consoleErrors.push(`pageerror: ${error.message}`);
      consoleLines.push(`pageerror: ${error.message}`);
    });
    page.on('console', (message) => {
      if (message.type() === 'error') {
        consoleErrors.push(`console: ${message.text()}`);
        consoleLines.push(`console: ${message.text()}`);
      }
    });

    // Observe downloads through the browser's own download manager.
    const cdp = await page.createCDPSession();
    const downloads = [];
    await cdp.send('Browser.setDownloadBehavior', {
      behavior: 'allowAndName',
      downloadPath: downloadDir,
      eventsEnabled: true,
    });
    cdp.on('Browser.downloadWillBegin', (event) => {
      downloads.push({
        url: event.url,
        suggested: event.suggestedFilename,
        guid: event.guid,
        done: false,
      });
    });
    cdp.on('Browser.downloadProgress', (event) => {
      const entry = downloads.find((item) => item.guid === event.guid);
      if (entry) entry.done = event.state === 'completed';
    });

    const network = [];
    page.on('request', (request) =>
      network.push({
        url: request.url(),
        method: request.method(),
        post: request.postData(),
      }),
    );

    // What the program asked the server for, counted.
    //
    // A button that does nothing and a client that is stuck in a loop look
    // identical from the outside until somebody counts the requests. This is
    // that count: every call under /api/v1, grouped by the path without its
    // query, so `the reports screen asked for the trial balance 40 times` is a
    // line in the log rather than a mystery in the rate limiter.
    const traffic = new Map();
    page.on('request', (request) => {
      const url = request.url();
      const at = url.indexOf('/api/v1/');
      if (at === -1) return;
      const path = url.slice(at).split('?')[0];
      const key = `${request.method()} ${path}`;
      traffic.set(key, (traffic.get(key) ?? 0) + 1);
    });

    /** The busiest routes, as one line: `GET /api/v1/health x12, ...`. */
    const trafficNote = (limit = 8) =>
      [...traffic.entries()]
        .sort((a, b) => b[1] - a[1])
        .slice(0, limit)
        .map(([route, count]) => `${route} x${count}`)
        .join(', ') || 'no API call was seen';

    const trafficTotal = () => [...traffic.values()].reduce((a, b) => a + b, 0);

    // Every request the program made that came back refused, with the route
    // that refused it. A button that downloads nothing and a page that shows
    // nothing have the same shape from the outside; what tells them apart is
    // the address that came back 401, and whether it carried the credential
    // it was supposed to. These lines are printed into the log and carried
    // into the detail of the check that failed, so the annotation of a
    // failing run names the route rather than the symptom.
    const refused = [];
    page.on('response', (response) => {
      const status = response.status();
      if (status < 400) return;
      const url = response.url();
      if (!/\/api\//.test(url)) return;
      const path = url.replace(/^https?:\/\/[^/]+/, '');
      const line = `HTTP ${status} ${response.request().method()} ${path}`;
      if (!refused.includes(line)) refused.push(line);
      log(line);
    });

    // A file the program handed over, as the browser itself saw it.
    //
    // The download events are the nicer evidence — a name, a finished
    // transfer, bytes on a disk — but the app saves a fetched file from an
    // object URL inside the click, and whether that shows up as a download
    // depends on the browser build as much as on the program. So the answer
    // the browser got for the file route is recorded here too: 200, an
    // attachment header and a body with real length is the promise kept,
    // whichever way it reached the person's Downloads folder.
    const fileAnswers = [];
    page.on('response', async (response) => {
      const url = response.url();
      if (!/\/api\/v1\/.*\/(download|pdf|print|templates\/)/.test(url)) return;
      const headers = response.headers();
      const answer = {
        url,
        path: url.replace(/^https?:\/\/[^/]+/, ''),
        status: response.status(),
        size: Number(headers['content-length'] ?? 0),
        attachment: (headers['content-disposition'] ?? '').includes('attachment'),
        type: headers['content-type'] ?? '',
      };
      fileAnswers.push(answer);
      log(
        `FILE ${answer.status} ${answer.path.split('?')[0]} ` +
          `${answer.size}B${answer.attachment ? ' attachment' : ''}`,
      );
    });

    /** The most recent successful answer for a route matching [needle]. */
    const fileAnswerFor = (needle, since) =>
      fileAnswers
        .slice(since)
        .reverse()
        .find((answer) => answer.status === 200 && needle.test(answer.path)) ?? null;

    /// The refusals worth quoting in a check's detail: the ones seen so far,
    /// oldest first, and never the whole list.
    const refusedNote = () =>
      refused.length === 0
        ? 'no request was refused'
        : `refused: ${refused.slice(-3).join(' , ')}`;

    // Anything the server could not do. A 500 the server logged is worth
    // more than a click that found nothing, so each one is printed with the
    // sentence the server sent back about it.
    const serverErrors = [];
    page.on('response', async (response) => {
      if (response.status() < 500) return;
      let body = '';
      try {
        body = (await response.text()).replace(/\s+/g, ' ').slice(0, 300);
      } catch {
        body = '(the body was gone before it could be read)';
      }
      serverErrors.push(`${response.status()} ${response.url()} ${body}`);
      log(`SERVER ${response.status()} ${response.url()} ${body}`);
    });

    // What the server answered. The one response that matters most is the
    // sign-in: if the screen does not move, the reason is in that status
    // code and not in the clicking.
    const responses = [];
    page.on('response', async (response) => {
      const url = response.url();
      if (!/\/auth\/(login|refresh|download-ticket)/.test(url)) return;
      let body = '';
      try {
        body = (await response.text()).slice(0, 300);
      } catch {
        body = '(the body was gone before it could be read)';
      }
      responses.push({ url, status: response.status(), body });
      log(`LOGIN ${response.status()} ${url.split('/api/v1')[1] ?? url} ${body}`);
    });

    const shot = async (name) => {
      const path = join(OUT_DIR, `${name}.png`);
      await page.screenshot({ path }).catch(() => {});
      return path;
    };

    /**
     * Every label the page publishes, so a click that finds nothing can say
     * what was there instead of just that it found nothing.
     */
    const publishedLabels = () =>
      page.evaluate(() =>
        Array.from(
          document.querySelectorAll(
            'flt-semantics, [role="button"], [role="menuitem"], [role="tab"], [role="textbox"], [role="link"]',
          ),
        )
          .map((node) => ({
            label: (node.getAttribute('aria-label') || '').trim(),
            text: (node.textContent || '').trim().slice(0, 60),
            role: node.getAttribute('role') || node.tagName.toLowerCase(),
          }))
          .filter((node) => node.label || node.text),
      );

    /**
     * Everything the page will admit to, printed into the log.
     *
     * CI artifacts are a luxury a failing run does not always get read, so
     * what a stuck click needs to say has to reach the log itself. Each
     * line is prefixed so the workflow can lift them into annotations.
     */
    async function describe(step) {
      try {
        const labels = await publishedLabels();
        writeFileSync(
          join(OUT_DIR, `labels-${step}.json`),
          JSON.stringify(labels, null, 2),
        );
        const names = labels
          .map((node) => `${node.label || node.text}[${node.role}]`)
          .filter(Boolean);
        for (let index = 0; index < names.length; index += 6) {
          log(`LABELS ${step}: ${names.slice(index, index + 6).join(' | ')}`);
        }
        const inputs = await page.$$eval('input', (nodes) =>
          nodes.map((node) => ({
            type: node.type,
            hidden: node.hidden,
            aria: node.getAttribute('aria-label') || '',
            rect: (() => {
              const r = node.getBoundingClientRect();
              return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width) };
            })(),
          })),
        );
        writeFileSync(join(OUT_DIR, `inputs-${step}.json`), JSON.stringify(inputs, null, 2));
        log(`INPUTS ${step}: ${inputs.length} input element(s)`);
        for (const input of inputs.slice(0, 6)) {
          log(
            `INPUTS ${step}: type=${input.type} hidden=${input.hidden} ` +
              `at ${input.rect.x},${input.rect.y} aria="${input.aria}"`,
          );
        }
        const visible = await page.evaluate(() =>
          (document.body.innerText || '').replace(/\s+/g, ' ').slice(0, 300),
        );
        log(`SCREEN ${step}: ${visible}`);
      } catch (error) {
        log(`LABELS ${step}: could not be read - ${error.message}`);
      }
    }

    /**
     * One line saying where the browser actually is, after a step that was
     * supposed to move it.
     *
     * `FAIL  the reports entry opens - at http://...#/dashboard` tells a
     * reader nothing about the page; this says which controls were up at the
     * moment the click was expected to have landed, which is what a wording
     * change or a refused permission looks like from the outside.
     */
    async function navNote(step, stillOnLogin) {
      try {
        const labels = await publishedLabels();
        const names = labels
          .map((node) => (node.label || node.text).trim())
          .filter(Boolean)
          .slice(0, 16);
        const url = page.url();
        log(
          `NAV ${step}: url=${url}` +
            (stillOnLogin ? ` still-on-login=${stillOnLogin()}` : '') +
            ` controls=[${names.join(' | ')}]`,
        );
      } catch (error) {
        log(`NAV ${step}: could not be read - ${error.message}`);
      }
    }

    /**
     * The centre of the smallest Flutter semantic node whose name includes
     * one of [names].
     *
     * Smallest, not first: the accessibility tree is nested, and the outer
     * node of the login screen carries the same words as the button inside
     * it because it contains that button. Taking the first match clicks the
     * middle of the whole screen. Taking the smallest clicks the control the
     * words belong to.
     */
    async function findNode(names, roles) {
      const found = await findAllNodes(names, roles);
      return found.length > 0 ? found[0] : null;
    }

    /** Every matching node, smallest first. */
    async function findAllNodes(names, roles) {
      const wanted = names.map((name) => name.toLowerCase());
      return page.evaluate(
        (needles, roleList) => {
          const selector =
            roleList.length > 0
              ? roleList.map((role) => `[role="${role}"]`).join(', ')
              : 'flt-semantics, [role="button"], [role="menuitem"], [role="tab"], [role="textbox"], [role="link"]';
          const matches = [];
          for (const node of Array.from(document.querySelectorAll(selector))) {
            const label = `${node.getAttribute('aria-label') || ''} ${node.textContent || ''}`;
            const lower = label.toLowerCase();
            if (!needles.some((needle) => lower.includes(needle))) continue;
            const rect = node.getBoundingClientRect();
            if (rect.width <= 0 || rect.height <= 0) continue;
            const role = node.getAttribute('role') || '';
            matches.push({
              x: rect.x + rect.width / 2,
              y: rect.y + rect.height / 2,
              area: rect.width * rect.height,
              isControl: /^(button|menuitem|tab|link|textbox|checkbox|switch|radio)$/i.test(role),
              role,
              label: label.trim().slice(0, 40),
            });
          }
          // A screen can say the same words twice - the login screen has a
          // heading "Sign in" and a button "Sign in". The one that can be
          // pressed says so, so the controls are preferred over the plain
          // text before the smallest is chosen.
          const controls = matches.filter((match) => match.isControl);
          const pool = controls.length > 0 ? controls : matches;
          pool.sort((a, b) => a.area - b.area);
          return pool;
        },
        wanted,
        roles,
      );
    }

    /**
     * Clicks the first control whose label contains one of [names].
     *
     * Two languages are offered because the app follows the browser's
     * language: a check that only knows the Arabic wording breaks the day
     * somebody opens it in English, and vice versa.
     */
    async function clickNamed(names, { timeoutMs = 10000, step = 'click' } = {}) {
      const list = Array.isArray(names) ? names : [names];
      const deadline = Date.now() + timeoutMs;
      while (Date.now() < deadline) {
        const at = await findNode(list, []);
        if (at) {
          log(`CLICK ${step}: "${at.label}" at ${Math.round(at.x)},${Math.round(at.y)}`);
          await page.mouse.click(at.x, at.y);
          return true;
        }
        await wait(250);
      }
      log(`LABELS missed: nothing labelled ${list.join(' / ')} was found at step ${step}`);
      await describe(step);
      return false;
    }

    const clickField = (names, step) =>
      clickNamed(names, { timeoutMs: 10000, step });

    async function waitForDownload(previousCount, timeoutMs = 30000) {
      const deadline = Date.now() + timeoutMs;
      while (Date.now() < deadline) {
        const fresh = downloads.slice(previousCount);
        if (fresh.length && fresh.every((item) => item.done)) break;
        await wait(250);
      }
      const fresh = downloads.slice(previousCount);
      // Say what arrived, and whether it arrived whole: a download that was
      // still open when the timer ran out is a different thing from one that
      // never started, and the log has to be able to tell them apart.
      log(
        `DOWNLOAD ${fresh.length === 0 ? 'nothing arrived' : fresh.map((item) => `${item.suggested}${item.done ? '' : ' (incomplete)'}`).join(', ')}`,
      );
      return fresh.filter((item) => item.done);
    }

    const bytesOf = (entry) => {
      const byGuid = join(downloadDir, entry.guid);
      const byName = join(downloadDir, entry.suggested);
      const path = existsSync(byGuid) ? byGuid : existsSync(byName) ? byName : null;
      return path ? readFileSync(path) : Buffer.alloc(0);
    };

    // ───────────────────────────────────────────────────── 1. sign in
    // `a11y=1` is the program's own switch: on the web Flutter only
    // publishes the tree of button names when something asks for it, and
    // these checks follow names rather than pixels.
    const separator = APP_URL.includes('?') ? '&' : '?';
    await page.goto(`${APP_URL}${separator}a11y=1`, {
      waitUntil: 'networkidle2',
      timeout: 90000,
    });
    await wait(6000); // Flutter's first paint
    await shot('01-login');
    await describe('01-login');

    const published = await publishedLabels();
    check(
      'the program publishes the names of its controls',
      published.length > 3 &&
        !published.every((node) => /enable accessibility/i.test(node.label || '')),
      `${published.length} named control(s)` +
        (published.length <= 3
          ? ` - only: ${published.map((node) => node.label || node.text).join(' | ')}`
          : ''),
    );
    if (published.length <= 3) return 1;

    // Flutter web keeps a real <input> element for each text field, so the
    // credentials are typed into those rather than into a guessed point on
    // the screen. The labelled-node route stays as the fallback.
    /** Every value the text fields currently hold, empty ones left out. */
    const fieldValues = () =>
      page.$$eval('input', (nodes) =>
        nodes.map((node) => node.value ?? '').filter((value) => value !== ''),
      );

    /**
     * Puts one value into the field at [box].
     *
     * Typing into a canvas-drawn field loses the first keystroke often
     * enough to matter - the click that focuses the field is still being
     * handled when the first character arrives. So each attempt starts by
     * emptying the field, types slowly, and then reads the value back: what
     * is asserted is not that keys were pressed but that the field holds
     * what it should.
     */
    async function typeIntoField(box, value) {
      for (let attempt = 0; attempt < 3; attempt += 1) {
        await page.mouse.click(box.x, box.y);
        await wait(300);
        await page.keyboard.down('Control');
        await page.keyboard.press('KeyA');
        await page.keyboard.up('Control');
        await page.keyboard.press('Backspace');
        await wait(120);
        await page.keyboard.type(value, { delay: 40 });
        await wait(150);
        const values = await fieldValues();
        if (values.includes(value)) return true;
        log(
          `INPUTS attempt ${attempt + 1} put ${JSON.stringify(values)} in the fields, not "${value}"`,
        );
      }
      return false;
    }

    async function typeIntoFields(values) {
      const inputs = await page.$$('input');
      const usable = [];
      for (const input of inputs) {
        const box = await input.evaluate((node) => {
          if (node.hidden || node.type === 'hidden') return null;
          const rect = node.getBoundingClientRect();
          if (rect.width <= 0 || rect.height <= 0) return null;
          return { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 };
        });
        if (box) usable.push({ input, box });
      }
      if (usable.length < values.length) return false;
      for (let index = 0; index < values.length; index += 1) {
        // Flutter's text fields are drawn on the canvas; the <input> is a
        // real element sitting on top of them, and a synthetic click on it
        // does not always land. Clicking where it is does.
        const ok = await typeIntoField(usable[index].box, values[index]);
        if (!ok) return false;
      }
      log(`INPUTS typed: ${JSON.stringify(await fieldValues())}`);
      return true;
    }

    let typed =
      (await typeIntoFields([USERNAME, PASSWORD]).catch(() => false)) === true;
    if (!typed) {
      const typedUser = await clickField(['اسم المستخدم', 'Username'], 'user-field');
      await page.keyboard.type(USERNAME);
      const typedPassword = await clickField(['كلمة المرور', 'Password'], 'password-field');
      await page.keyboard.type(PASSWORD);
      typed = typedUser && typedPassword;
    }
    await shot('02-credentials');
    await wait(500);

    const beforeLoginResponse = responses.length;
    await clickNamed(['تسجيل الدخول', 'Sign in'], { step: 'signin-button' });

    /**
     * Whether the browser is still looking at the sign-in page.
     *
     * The address is the first thing to ask, because the router is what moves
     * it: `#/login` while signed out, `#/dashboard` once the session exists.
     * It is not the only thing to ask though. A single-page app can be signed
     * in and still be mid-paint, and a check that reads the address once per
     * second for eight seconds has decided the program is broken before the
     * program has finished. So the page is asked twice: by address, and by
     * the controls it publishes - the workspace has a reports button and the
     * login page does not, which is the surer sign of the two.
     */
    const atLoginPage = () => /login|signin|setup/.test(page.url());
    const workspaceIsUp = async () =>
      (await findAllNodes(['التقارير', 'Reports', 'القيود', 'Journal'], []).catch(
        () => [],
      ))
        .then((nodes) => nodes.length > 0);

    let signedIn = false;
    for (let attempt = 0; attempt < 12 && !signedIn; attempt += 1) {
      await wait(1000);
      signedIn = !atLoginPage() || (await workspaceIsUp());
    }

    if (!signedIn) {
      // A form that is filled in usually submits on Enter too. Trying it is
      // cheaper than a run that reports a sign-in it never attempted.
      log('LOGIN the button did not move the page; trying Enter');
      await page.keyboard.press('Enter');
      for (let attempt = 0; attempt < 12 && !signedIn; attempt += 1) {
        await wait(1000);
        signedIn = !atLoginPage() || (await workspaceIsUp());
      }
    }

    const loginResponse = responses
      .slice(beforeLoginResponse)
      .find((entry) => /\/auth\/login/.test(entry.url));
    if (loginResponse) {
      log(`LOGIN sign-in answered ${loginResponse.status}`);
    }
    // The workspace loads its first numbers after the session exists, and the
    // screens the checks click are behind that. Give it a moment to settle,
    // then write down where the browser ended up.
    await wait(4000);
    await shot('03-after-signin');
    const at = page.url();
    await navNote('after-signin', atLoginPage);
    check(
      'sign in opens the workspace',
      typed && signedIn,
      `now at ${at}` +
        (loginResponse ? `, sign-in answered ${loginResponse.status}` : ', no answer seen'),
    );
    if (!signedIn) {
      await describe('after-signin');
      return 1;
    }

    // ───────────────────────────────────────────── 2. export download
    const before = downloads.length;
    const beforeExcelAnswer = fileAnswers.length;
    const wentToReports = await clickNamed(['التقارير', 'Reports'], { step: 'nav-reports' });
    await wait(5000);
    await shot('04-reports');
    await navNote('nav-reports');
    check('the reports entry opens', wentToReports, `at ${page.url()}`);

    // A period has to be chosen before a report has anything to show.
    await clickNamed(['عرض التقرير', 'ميزان المراجعة', 'Trial balance', 'Show report'], {
      timeoutMs: 6000,
      step: 'report-choose',
    }).catch(() => false);
    await wait(3000);

    const clickedExcel = await clickNamed(['إكسل', 'Excel'], { step: 'export-excel' });
    const arrived = await waitForDownload(before);
    if (arrived.length === 0) await describe('export-excel');
    const excelAnswer = fileAnswerFor(/exports\/.*\/download/, beforeExcelAnswer);
    check(
      'an export button downloads a spreadsheet file',
      clickedExcel && (arrived.length > 0 || (excelAnswer?.size ?? 0) > 500),
      arrived.map((item) => item.suggested).join(', ') ||
        (excelAnswer
          ? `the browser was handed ${excelAnswer.size} bytes of ${excelAnswer.type}`
          : `nothing arrived - ${refusedNote()}; traffic: ${trafficNote(4)}`),
    );
    if (arrived.length) {
      const bytes = bytesOf(arrived[arrived.length - 1]);
      check(
        'the downloaded file is a real spreadsheet',
        bytes.length > 500 && bytes.subarray(0, 2).toString('latin1') === 'PK',
        `${bytes.length} bytes, ${bytes.subarray(0, 2).toString('latin1')} signature`,
      );
    }

    // ───────────────────────────────────────────── 3. print page
    const beforeTabs = (await browser.pages()).length;
    const beforePrintAnswer = fileAnswers.length;
    const clickedPrint = await clickNamed(['طباعة', 'Print'], { step: 'print' });
    await wait(6000);
    await describe('print');
    const pages = await browser.pages();
    const printPage = pages[pages.length - 1];
    const printUrl = pages.length > beforeTabs ? printPage.url() : page.url();
    const printAnswer = fileAnswerFor(/\/print/, beforePrintAnswer);
    check(
      'the print button reaches a print page',
      clickedPrint && (/\/print/.test(printUrl) || printAnswer !== null),
      /\/print/.test(printUrl)
        ? printUrl
        : printAnswer
          ? `the page was answered (${printAnswer.status}, ${printAnswer.size}B) ` +
            `while the tab stayed at ${printUrl}`
          : `${printUrl} - ${refusedNote()}`,
    );
    if (pages.length > beforeTabs) {
      await printPage
        .screenshot({ path: join(OUT_DIR, '05-print-page.png') })
        .catch(() => {});
      await printPage.close().catch(() => {});
      await page.bringToFront();
    }

    // ───────────────────────────────── 4. import template + file choose
    const beforeTemplate = downloads.length;
    const beforeTemplateAnswer = fileAnswers.length;
    const wentToImport = await clickNamed(['رفع بيانات', 'Import'], { step: 'nav-import' });
    await wait(5000);
    await shot('06-import');
    await navNote('nav-import');
    check('the import entry opens', wentToImport, `at ${page.url()}`);

    const clickedTemplate = await clickNamed(['تنزيل القالب', 'القالب', 'template', 'Template'], {
      step: 'import-template',
    });
    const templateArrived = await waitForDownload(beforeTemplate);
    if (templateArrived.length === 0) await describe('import-template');
    const templateAnswer = fileAnswerFor(/import\/templates\//, beforeTemplateAnswer);
    check(
      'the template button downloads a file',
      clickedTemplate &&
        (templateArrived.length > 0 || (templateAnswer?.size ?? 0) > 500),
      templateArrived.map((item) => item.suggested).join(', ') ||
        (templateAnswer
          ? `the browser was handed ${templateAnswer.size} bytes of ${templateAnswer.type}`
          : `nothing arrived - ${refusedNote()}`),
    );

    // Choosing a file: the real system dialogue is driven through CDP.
    const dryRunMark = network.length;
    let choseFile = false;
    try {
      const [chooser] = await Promise.all([
        page.waitForFileChooser({ timeout: 10000 }),
        clickNamed(['ملف', 'file', 'File'], { timeoutMs: 10000, step: 'choose-file' }),
      ]);
      // A small spreadsheet the server can parse, written here so the tool
      // travels alone.
      const fixture = join(OUT_DIR, 'import-fixture.csv');
      writeFileSync(fixture, 'code,name_ar,name_en\nE2E-1,اختبار,Check\n');
      await chooser.accept([fixture]);
      choseFile = true;
    } catch {
      choseFile = false;
    }
    await wait(7000);
    await shot('07-after-file');
    const dryRunCalls = network
      .slice(dryRunMark)
      .filter(
        (request) =>
          /import\/.*dry/i.test(request.url) ||
          (/import\//.test(request.url) && request.method === 'POST'),
      );
    check(
      'choosing a file makes the app read it on the server',
      choseFile && dryRunCalls.length > 0,
      choseFile ? `${dryRunCalls.length} read request(s)` : 'no file chooser opened',
    );
    if (!choseFile) await describe('choose-file');

    // Closing the dialogue without a file must not wedge the button.
    let cancelRecovered = false;
    try {
      for (let attempt = 0; attempt < 2; attempt += 1) {
        const [chooser] = await Promise.all([
          page.waitForFileChooser({ timeout: 10000 }),
          clickNamed(['ملف', 'file', 'File'], { timeoutMs: 10000, step: 'choose-file' }),
        ]);
        await chooser.dismiss();
        // Long enough for the bar at the bottom of the screen to go away. A
        // file that was just read leaves a sentence on the screen, and that
        // sentence sits over the button: clicking a moment later presses the
        // message, not the control, and the check would then report a wedged
        // button where there is only a snackbar in the way.
        await wait(6000);
      }
      cancelRecovered = true;
    } catch {
      cancelRecovered = false;
    }
    check('closing the file dialogue twice in a row is fine', cancelRecovered);

    // ───────────────────────────────────────────── 5. full backup
    const beforeBackup = network.length;
    const beforeDump = downloads.length;
    const beforeDumpAnswer = fileAnswers.length;
    const wentToBackup = await clickNamed(['النسخ الاحتياطي', 'Backup'], { step: 'nav-backup' });
    await wait(5000);
    await shot('08-backup');
    await navNote('nav-backup');
    check('the backup entry opens', wentToBackup, `at ${page.url()}`);

    const clickedCreate = await clickNamed(['إنشاء نسخة', 'Create full backup'], {
      timeoutMs: 15000,
      step: 'create-backup',
    });
    await wait(25000);
    await shot('09-backup-made');
    const backupCalls = network
      .slice(beforeBackup)
      .filter((request) => /backup\/full/.test(request.url) && request.method === 'POST');
    check(
      'the backup button asks the server for a full backup',
      clickedCreate && backupCalls.length > 0,
      `${backupCalls.length} backup request(s)`,
    );

    const clickedDump = await clickNamed(['تنزيل', 'Download'], { step: 'download-backup' });
    const dumpArrived = await waitForDownload(beforeDump);
    if (dumpArrived.length === 0) await describe('download-backup');
    const dumpAnswer = fileAnswerFor(/backup\/full\/.*\/download/, beforeDumpAnswer);
    check(
      'the backup file downloads',
      clickedDump && (dumpArrived.length > 0 || (dumpAnswer?.size ?? 0) > 500),
      dumpArrived.map((item) => item.suggested).join(', ') ||
        (dumpAnswer
          ? `the browser was handed ${dumpAnswer.size} bytes`
          : `no download arrived - ${refusedNote()}`),
    );
    if (dumpArrived.length) {
      const bytes = bytesOf(dumpArrived[dumpArrived.length - 1]);
      const magic = bytes.subarray(0, 5).toString('latin1');
      check(
        'the backup is a PostgreSQL archive',
        magic === 'PGDMP',
        `${bytes.length} bytes, magic=${JSON.stringify(magic)}`,
      );
    }

    // ───────────────────────────────────────────────────────── summary
    log(`TRAFFIC ${trafficTotal()} API call(s): ${trafficNote(10)}`);
    if (trafficTotal() > 120) {
      log(
        `TRAFFIC warning: ${trafficTotal()} calls for one visit through four ` +
          'screens is a client that is asking again, not a person clicking. ' +
          'Behind the rate limiter this is what turns a button into nothing.',
      );
    }
    await shot('10-final');
    check(
      'the page raised no uncaught errors of its own',
      consoleErrors.filter((line) => !/favicon|fonts\.g/i.test(line)).length === 0,
      `${consoleErrors.slice(0, 3).join(' / ') || 'none'}${refused.length ? ` | ${refusedNote()}` : ''}`,
    );
    check(
      'the server answered every request the program made',
      serverErrors.length === 0,
      serverErrors.slice(0, 3).join(' | ') || 'no 5xx was seen',
    );
  } finally {
    await browser.close().catch(() => {});
  }

  const failures = results.filter((result) => !result.ok);
  log(
    `\n${results.length - failures.length}/${results.length} checks passed` +
      (failures.length
        ? `\nFAILED: ${failures.map((entry) => entry.name).join('\n       ')}`
        : ''),
  );
  save();
  return failures.length ? 1 : 0;
}

mkdirSync(OUT_DIR, { recursive: true });

main()
  .then((code) => {
    // Not process.exit: it would cut the log off mid-sentence. Setting the
    // code lets Node finish writing and leave on its own.
    process.exitCode = code;
  })
  .catch((error) => {
    log(`the browser check itself broke: ${error?.stack ?? error}`);
    results.push({
      name: 'the check ran to the end',
      ok: false,
      detail: String(error?.message ?? error),
    });
    save();
    process.exitCode = 2;
  });
