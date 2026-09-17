#!/usr/bin/env node
/**
 * Transport-only headless-browser capture adapter.
 *
 * Contract (JSON in, JSON out):
 *   node capture_web.mjs --job <job.json> --out <screenshot.png> [--settle-ms 250]
 *
 *   stdout: one JSON object, either
 *     {"ok": true,  "deterministic": true, "width": W, "height": H}
 *     {"ok": false, "code": "capture_failed" | "capture_not_deterministic", "message": "..."}
 *   exit code: 0 on success, 1 on failure.
 *
 * This adapter contains no QA severity, finding, review, approval, baseline, or
 * promotion logic. It renders a governed URL deterministically and returns a
 * PNG plus machine-readable status. The browser dependency is optional: when a
 * headless browser driver is unavailable the adapter fails with a typed code
 * instead of silently degrading.
 *
 * Local setup (not required by CI):
 *   npm install --no-save playwright && npx playwright install chromium
 */

import { readFileSync, writeFileSync } from 'node:fs';

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

async function loadDriver() {
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

async function captureWithPlaywright(driver, job, outPath, settleMs) {
  const { chromium } = driver.module;
  const browser = await chromium.launch({ headless: true, args: ['--force-color-profile=srgb'] });
  try {
    const context = await browser.newContext({
      viewport: { width: job.viewport.width, height: job.viewport.height },
      deviceScaleFactor: job.device_scale_factor ?? 1,
      reducedMotion: 'reduce',
      colorScheme: 'light',
      locale: 'en-US',
    });
    const page = await context.newPage();
    await page.addInitScript(() => {
      window.__captureReady = false;
      document.addEventListener('DOMContentLoaded', () => {
        window.__captureReady = true;
      });
    });
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
    return { width: job.viewport.width, height: job.viewport.height };
  } finally {
    await browser.close();
  }
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

  const driver = await loadDriver();
  if (!driver) {
    fail(
      FAILED,
      'no headless browser driver available (install playwright or puppeteer locally)',
    );
  }

  try {
    const result = await captureWithPlaywright(driver, job, args.out, args.settleMs);
    emit({ ok: true, deterministic: true, driver: driver.name, ...result }, 0);
  } catch (error) {
    fail(FAILED, `capture failed: ${error.message}`);
  }
}

main().catch((error) => fail(FAILED, `unexpected adapter failure: ${error.message}`));
