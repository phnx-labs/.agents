#!/usr/bin/env node
// Record a scripted walkthrough of each reference site for design research (research.md).
// Per site: walkthrough.mp4 (pointer sweep, hovers, wheel scroll), three stills, a tech
// fingerprint, and a contact sheet (25 frames spread over the recording, 5 x 5).
//
//   node record-sites.mjs <sites.tsv> <out-dir> [--concurrency 3] [--chromium <path>]
//
// sites.tsv: one "slug<TAB>url" per line; lines starting with # are skipped. Needs the
// `playwright` package resolvable from the working directory (npm i playwright, then
// npx playwright install chromium) and ffmpeg on PATH. Heavy WebGL sites may record only a
// loader under software rendering; the notes must say so rather than invent the effect.
import { readFileSync, mkdirSync, existsSync, renameSync, appendFileSync, writeFileSync, unlinkSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join } from "node:path";
import { createRequire } from "node:module";

const args = process.argv.slice(2);
const flag = (name, fallback) => { const i = args.indexOf(name); return i >= 0 ? args.splice(i, 2)[1] : fallback; };
const concurrency = Number(flag("--concurrency", "3"));
if (!Number.isInteger(concurrency) || concurrency < 1) { console.error("--concurrency must be a whole number of 1 or more"); process.exit(2); }
const chromiumPath = flag("--chromium", undefined);
const [sitesFile, out] = args;
if (!sitesFile || !out) { console.error("usage: node record-sites.mjs <sites.tsv> <out-dir> [--concurrency 3] [--chromium <path>]"); process.exit(2); }

let chromium;
try { ({ chromium } = createRequire(join(process.cwd(), "noop.js"))("playwright")); }
catch { console.error("playwright is not installed here. Run: npm i playwright && npx playwright install chromium"); process.exit(1); }
try { execFileSync("ffmpeg", ["-version"], { stdio: "ignore" }); }
catch { console.error("ffmpeg is not on PATH; it converts the recordings and builds contact sheets."); process.exit(1); }

const W = 1440, H = 900, DEADLINE_MS = 110000;
const failures = [];
const sites = readFileSync(sitesFile, "utf8").split("\n").map((l) => l.trim()).filter((l) => l && !l.startsWith("#")).map((l) => l.split("\t"));
mkdirSync(out, { recursive: true });
const log = (m) => { const line = `${new Date().toISOString().slice(11, 19)} ${m}\n`; process.stdout.write(line); appendFileSync(join(out, "run.log"), line); };

// Detected in the page: which libraries and techniques a move was built with.
const FINGERPRINT = () => {
  const cssHas = (re) => { let unreadable = false; for (const sheet of document.styleSheets) { let rules; try { rules = [...sheet.cssRules]; } catch { unreadable = true; continue; } if (rules.some((r) => re.test(r.cssText))) return true; } return unreadable ? null : false; };
  return {
  title: document.title,
  gsap: !!window.gsap,
  lenis: !!(window.lenis || window.Lenis || document.documentElement.classList.contains("lenis")),
  three: window.__THREE__ || (window.THREE ? "global" : null),
  webglCanvas: [...document.querySelectorAll("canvas")].some((c) => { try { return !!(c.getContext("webgl2") || c.getContext("webgl")); } catch { return false; } }),
  framer: !!document.querySelector("[data-framer-name],[data-framer-component-type]"),
  nextjs: !!document.querySelector('script[src*="/_next/"]'),
  lottie: !!document.querySelector("lottie-player,dotlottie-player"),
  rive: !!window.rive,
  splitText: document.querySelectorAll('.char,.word,[data-split],.split-line').length,
  // true when found, false when every stylesheet was readable and none had it, null when a
  // cross-origin stylesheet could not be read, so absence is unknown rather than false.
  scrollDrivenCss: cssHas(/animation-timeline|view-timeline|scroll-timeline/),
  viewTransitions: cssHas(/view-transition/),
  reducedMotionCss: cssHas(/prefers-reduced-motion/),
  fonts: [...new Set([...document.fonts].filter((f) => f.status === "loaded").map((f) => f.family.replace(/["']/g, "")))].slice(0, 10),
  docHeight: document.documentElement.scrollHeight,
  };
};

async function walk(page, dir, url) {
  // A load timeout still leaves a page worth recording; an error page (DNS, refused, HTTP 4xx/5xx) does not.
  const response = await page.goto(url, { waitUntil: "load", timeout: 45000 }).catch((e) => { if (/Timeout/.test(e.message)) return null; throw e; });
  if (response && response.status() >= 400) throw new Error(`HTTP ${response.status()}`);
  await page.waitForTimeout(5000);
  for (const label of ["Accept", "Accept all", "I agree", "Got it", "Allow all"]) {
    const b = page.getByRole("button", { name: label, exact: true }).first();
    if (await b.isVisible({ timeout: 300 }).catch(() => false)) { await b.click({ timeout: 2000 }).catch(() => {}); await page.waitForTimeout(1000); }
  }
  await page.screenshot({ path: join(dir, "01-hero.png"), timeout: 20000 }).catch(() => {});
  for (const [x0, y0, x1, y1] of [[0.2, 0.3, 0.8, 0.55], [0.8, 0.55, 0.35, 0.75], [0.35, 0.75, 0.5, 0.4]]) {
    await page.mouse.move(W * x0, H * y0); await page.mouse.move(W * x1, H * y1, { steps: 45 });
  }
  const targets = await page.$$eval("a,button", (els) => els.map((e) => { const r = e.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2, w: r.width, h: r.height }; })
    .filter((r) => r.w > 20 && r.h > 12 && r.y > 0 && r.y < innerHeight && r.x > 0 && r.x < innerWidth).slice(0, 5)).catch(() => []);
  for (const t of targets) { await page.mouse.move(t.x, t.y, { steps: 15 }); await page.waitForTimeout(700); }
  for (let i = 1; i <= 16; i++) {
    await page.mouse.move(W * (0.45 + 0.1 * Math.sin(i)), H * (0.5 + 0.15 * Math.cos(i)), { steps: 8 });
    await page.mouse.wheel(0, 420); await page.waitForTimeout(1300);
    if (i === 5) await page.screenshot({ path: join(dir, "02-mid.png"), timeout: 20000 }).catch(() => {});
    if (i === 12) await page.screenshot({ path: join(dir, "03-deep.png"), timeout: 20000 }).catch(() => {});
  }
  await page.mouse.wheel(0, -3000); await page.waitForTimeout(2500);
  writeFileSync(join(dir, "fingerprint.json"), JSON.stringify({ url, ...(await page.evaluate(FINGERPRINT).catch((e) => ({ error: e.message }))) }, null, 2));
}

async function record(browser, slug, url) {
  const dir = join(out, slug);
  if (existsSync(join(dir, "walkthrough.mp4"))) { log(`skip ${slug}`); return; }
  mkdirSync(dir, { recursive: true });
  const ctx = await browser.newContext({ viewport: { width: W, height: H }, recordVideo: { dir, size: { width: W, height: H } } });
  const page = await ctx.newPage();
  const t0 = Date.now(); let timer, failed = null;
  log(`start ${slug} ${url}`);
  try {
    // A heavy page can block the renderer so input never returns; cap each site and keep what was recorded.
    await Promise.race([walk(page, dir, url), new Promise((_, rej) => { timer = setTimeout(() => rej(new Error("site deadline")), DEADLINE_MS); })]);
  } catch (e) {
    const msg = e.message.split("\n")[0];
    // The deadline keeps a partial but real recording; anything else (bad URL, error page) is a failure.
    if (msg === "site deadline") log(`partial ${slug}: stopped at the ${DEADLINE_MS / 1000}s cap`); else failed = msg;
  }
  finally {
    clearTimeout(timer);
    const video = page.video();
    await Promise.race([ctx.close(), new Promise((r) => setTimeout(r, 20000))]);
    const raw = video ? await video.path().catch(() => null) : null;
    if (!failed && raw && existsSync(raw)) {
      try {
        const webm = join(dir, "walkthrough.webm"); renameSync(raw, webm);
        const mp4 = join(dir, "walkthrough.mp4");
        execFileSync("ffmpeg", ["-y", "-loglevel", "error", "-i", webm, "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "26", "-preset", "veryfast", "-movflags", "+faststart", mp4], { timeout: 120000 });
        // 25 frames spread over the whole recording, however long it ran.
        const secs = Math.max(1, (Date.now() - t0) / 1000);
        execFileSync("ffmpeg", ["-y", "-loglevel", "error", "-i", mp4, "-vf", `fps=${(25 / secs).toFixed(4)},scale=480:-1,tile=5x5:padding=4:color=black`, "-frames:v", "1", join(dir, "contact-sheet.jpg")], { timeout: 120000 });
      } catch (e) { failed = `ffmpeg: ${e.message.split("\n")[0]}`; }
    } else if (!failed) failed = "no recording was produced";
    // A failed site leaves no recording behind, so the skip check lets a re-run retry it.
    if (failed) for (const f of [raw, join(dir, "walkthrough.webm"), join(dir, "walkthrough.mp4")]) if (f && existsSync(f)) unlinkSync(f);
    if (failed) { failures.push(slug); log(`failed ${slug}: ${failed}`); }
    else log(`done ${slug} ${Math.round((Date.now() - t0) / 1000)}s`);
  }
}

// Chromium's sandbox needs Linux user namespaces, which some workers disable; macOS and Windows keep it.
const sandboxArgs = process.platform === "linux" ? ["--no-sandbox"] : [];
const browser = await chromium.launch({ executablePath: chromiumPath, args: [...sandboxArgs, "--enable-unsafe-swiftshader", "--use-angle=swiftshader", "--ignore-gpu-blocklist"] });
const queue = [...sites];
await Promise.all(Array.from({ length: concurrency }, async () => { while (queue.length) { const [slug, url] = queue.shift(); await record(browser, slug, url); } }));
await browser.close();
if (failures.length) { log(`failed: ${failures.join(", ")} (fix the URL or retry; a failed site leaves no walkthrough.mp4, so a re-run retries it)`); process.exitCode = 1; }
else log("all done");
