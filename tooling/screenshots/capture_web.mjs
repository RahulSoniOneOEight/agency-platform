#!/usr/bin/env node
/**
 * Transport-only headless-browser capture adapter.
 *
 * Contract (JSON in, JSON out):
 *   node capture_web.mjs --job <job.json> --out <screenshot.png> [--settle-ms 250]
 *
 *   stdout: one JSON object, either
 *     {"ok": true,  "deterministic": true, "driver": "...", "width": W, "height": H}
 *     {"ok": false, "code": "capture_failed" | "capture_not_deterministic", "message": "..."}
 *   exit code: 0 on success, 1 on failure.
 *
 * This adapter contains no QA severity, finding, review, approval, baseline, or
 * promotion logic. It renders a governed URL deterministically and returns a
 * PNG plus machine-readable status.
 *
 * Two deterministic drivers are supported, in order:
 *   1. a Node browser driver (playwright / puppeteer), when installed locally;
 *   2. a system Chromium/Chrome/Edge binary (no npm dependency), discovered via
 *      CHROME_PATH / CHROMIUM_PATH or a well-known install location.
 * When neither is available the adapter fails with a typed code rather than
 * silently degrading.
 *
 * Local setup for the highest-fidelity driver (never required by CI):
 *   npm install --no-save playwright && npx playwright install chromium
 */

import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const FAILED = 'capture_failed';
const NONDETERMINISTIC = 'capture_not_deterministic';

function parseArgs(argv) {
  const args = { settleMs: 250 };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === '--job') args.job = argv[++index];
    else if (token === '--out') args.out = argv[++index];
    else if (token === '--settle-ms') args.settleMs = Number(argv[++index]);
  }
  return args;
}

function emit(payload, exitCode) {
  process.stdout.write(`${JSON.stringify(payload)}\n`);
  process.exit(exitCode);
}

function fail(code, message) {
  emit({ ok: false, code, message }, 1);
}

async function loadNodeDriver() {
  for (const name of ['playwright', 'playwright-core', 'puppeteer']) {
    try {
      const module = await import(name);
      return { name, module: module.default ?? module };
    } catch {
      // try the next driver
    }
  }
  return null;
}

function findChromiumBinary() {
  const candidates = [
    process.env.CHROME_PATH,
    process.env.CHROMIUM_PATH,
    '/usr/bin/google-chrome',
    '/usr/bin/google-chrome-stable',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
    '/snap/bin/chromium',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  ];
  for (const candidate of candidates) {
    if (candidate && existsSync(candidate)) return candidate;
  }
  return null;
}

async function captureWithNodeDriver(driver, job, outPath, settleMs) {
  const { chromium } = driver.module;
  const browser = await chromium.launch({
    headless: true,
    args: ['--force-color-profile=srgb', '--hide-scrollbars'],
  });
  try {
    const context = await browser.newContext({
      viewport: { width: job.viewport.width, height: job.viewport.height },
      deviceScaleFactor: job.device_scale_factor ?? 1,
      reducedMotion: 'reduce',
      colorScheme: 'light',
      locale: 'en-US',
    });
    const page = await context.newPage();
    await page.goto(job.url, { waitUntil: 'load', timeout: 60000 });
    await page.addStyleTag({
      content: `*, *::before, *::after {
        animation-duration: 0s !important;
        animation-delay: 0s !important;
        transition-duration: 0s !important;
        transition-delay: 0s !important;
        caret-color: transparent !important;
      }`,
    });
    await page.evaluate(async () => {
      if (document.fonts && document.fonts.ready) {
        await document.fonts.ready;
      }
      await new Promise((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(resolve)),
      );
    });
    if (Number.isFinite(settleMs) && settleMs > 0) {
      await page.waitForTimeout(settleMs);
    }
    const buffer = await page.screenshot({ type: 'png' });
    writeFileSync(outPath, buffer);
    return { driver: driver.name, width: job.viewport.width, height: job.viewport.height };
  } finally {
    await browser.close();
  }
}

function captureWithChromiumBinary(binary, job, outPath, settleMs) {
  const budget = Math.max(1000, Math.round((settleMs || 250) * 8));
  const profileDir = mkdtempSync(join(tmpdir(), 'agency-capture-'));
  const args = [
    '--headless=new',
    '--disable-gpu',
    '--hide-scrollbars',
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-extensions',
    '--disable-background-networking',
    '--force-color-profile=srgb',
    `--force-device-scale-factor=${job.device_scale_factor ?? 1}`,
    `--user-data-dir=${profileDir}`,
    `--window-size=${job.viewport.width},${job.viewport.height}`,
    `--virtual-time-budget=${budget}`,
    `--screenshot=${outPath}`,
    job.url,
  ];
  let result;
  try {
    result = spawnSync(binary, args, { encoding: 'utf8', timeout: 120000 });
  } finally {
    rmSync(profileDir, { recursive: true, force: true });
  }
  if (result.error) {
    throw new Error(`chromium launch failed: ${result.error.message}`);
  }
  if (!existsSync(outPath)) {
    const detail = (result.stderr || '').split('\n').slice(-3).join(' ').trim();
    throw new Error(`chromium produced no screenshot (exit ${result.status}): ${detail}`);
  }
  return {
    driver: 'chromium-binary',
    width: job.viewport.width,
    height: job.viewport.height,
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.job || !args.out) {
    fail(FAILED, 'capture adapter requires --job and --out');
  }

  let job;
  try {
    job = JSON.parse(readFileSync(args.job, 'utf8'));
  } catch (error) {
    fail(FAILED, `cannot read capture job: ${error.message}`);
  }
  if (!job || typeof job.url !== 'string' || !job.viewport) {
    fail(FAILED, 'capture job requires a url and viewport');
  }

  const nodeDriver = await loadNodeDriver();
  if (nodeDriver) {
    try {
      const result = await captureWithNodeDriver(nodeDriver, job, args.out, args.settleMs);
      emit({ ok: true, deterministic: true, ...result }, 0);
    } catch (error) {
      fail(FAILED, `capture failed: ${error.message}`);
    }
  }

  const binary = findChromiumBinary();
  if (!binary) {
    fail(
      FAILED,
      'no headless browser available (install playwright locally or set CHROME_PATH)',
    );
  }
  try {
    const result = captureWithChromiumBinary(binary, job, args.out, args.settleMs);
    emit({ ok: true, deterministic: true, ...result }, 0);
  } catch (error) {
    fail(FAILED, `capture failed: ${error.message}`);
  }
}

main().catch((error) => fail(FAILED, `unexpected adapter failure: ${error.message}`));
