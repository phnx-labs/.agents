#!/usr/bin/env bun
// Static linter for the design-core anti-tells catalog (§6), offline-first
// doctrine (§1), and color-only meaning (§3) — the checks that are detectable
// from markup alone. Heuristic by design: every finding is a line to look at,
// not a verdict; the screenshot critique remains mandatory (design-core §9).
//
// Usage: bun check-tells.ts <file.html> [--strict]
//   --strict  exit 1 when any HIGH finding is present (for gates)
//
// Output: one line per finding — SEVERITY [tag] line N: what — fix.

import { readFileSync } from "node:fs";

const file = process.argv[2];
const strict = process.argv.includes("--strict");
if (!file) {
  console.error("usage: check-tells.ts <file.html> [--strict]");
  process.exit(2);
}
const src = readFileSync(file, "utf8");
const lines = src.split("\n");

type Sev = "HIGH" | "WARN" | "INFO";
const findings: { sev: Sev; tag: string; line: number; msg: string }[] = [];
const add = (sev: Sev, tag: string, line: number, msg: string) => findings.push({ sev, tag, line, msg });

const scan = (re: RegExp, cb: (m: RegExpMatchArray, lineNo: number, text: string) => void) => {
  lines.forEach((text, i) => {
    const m = text.match(re);
    if (m) cb(m, i + 1, text);
  });
};

// ── offline-first (§1): external network dependencies ────────────────────────
scan(/<(?:link|script|img|iframe)[^>]*(?:href|src)=["'](https?:\/\/[^"']+)/i, (m, n) =>
  add("HIGH", "offline", n, `external resource ${m[1].slice(0, 60)} — page breaks offline; inline it or use system fonts`));
scan(/@import\s+(?:url\()?["']?https?:\/\//i, (m, n) =>
  add("HIGH", "offline", n, `external @import — inline the CSS`));
scan(/url\(["']?https?:\/\//i, (m, n) =>
  add("HIGH", "offline", n, `CSS url() fetches a remote asset — embed as data: or drop it`));

// ── tell #1/#3: italic-serif display voice ───────────────────────────────────
const serifNames = /(Instrument Serif|Tiempos|Newsreader|GT Sectra|Playfair|Canela|Reckless|Editorial New|Freight|Lora|Cormorant)/i;
scan(serifNames, (m, n) =>
  add("WARN", "tell-1", n, `display serif "${m[1]}" — the italic-serif display look is the #1 AI tell; prefer a heavy sans (700/800) or mono display`));
scan(/font-style\s*:\s*italic/i, (m, n) =>
  add("WARN", "tell-1", n, `font-style:italic — if this styles a headline, quote, or accent word, it is the italic-accent tell; bold or mono-accent instead`));
scan(/<h[1-3][^>]*>[^<]*<(i|em)\b/i, (m, n) =>
  add("WARN", "tell-3", n, `<${m[1]}> inside a heading — italic mid-headline accent is a tell; use weight or color, not italics`));

// ── tell #2: two-tone muted headline ─────────────────────────────────────────
scan(/<h[12][^>]*>(?:(?!<\/h)[\s\S])*?class="[^"]*\b(?:text-(?:zinc|gray|slate|neutral|stone)-[45]00|muted|sub)\b/i, (m, n) =>
  add("WARN", "tell-2", n, `muted-tone span inside a headline — the bright/muted two-tone headline is a tell; one tone, hierarchy from size/weight`));

// ── tell #5: latin / typographic section markers ─────────────────────────────
scan(/[§№]/, (m, n) =>
  add("WARN", "tell-5", n, `"${m[0]}" section marker — use the most boring label possible ("01 / Features")`));
scan(/>\s*\d{2}\s*·\s*[A-Za-z]/, (m, n) =>
  add("INFO", "tell-5", n, `"NN · Title" section marker — borderline; fine alone, a tell in combination with serif italics + warm palette`));

// ── tell #6: sodium amber / warm cream on warm off-black (oklch heuristic) ───
const oklchAll = [...src.matchAll(/oklch\(\s*(0?\.\d+|1)\s+(0?\.\d+)\s+(\d+(?:\.\d+)?)/g)];
const darkWarmBg = oklchAll.some((m) => parseFloat(m[1]) < 0.3 && parseFloat(m[3]) >= 30 && parseFloat(m[3]) <= 99);
const warmAccent = oklchAll.some((m) => parseFloat(m[1]) >= 0.45 && parseFloat(m[2]) >= 0.1 && parseFloat(m[3]) >= 30 && parseFloat(m[3]) <= 90);
if (darkWarmBg && warmAccent)
  add("WARN", "tell-6", 0, `warm dark background + warm high-chroma accent (oklch hues 30–90) — the "sodium amber on warm off-black" palette is a tell; consider a real brand color or achromatic base`);

// ── tell #8: strikethrough metaphor headline ─────────────────────────────────
scan(/<h[12][^>]*>(?:(?!<\/h)[\s\S])*?<(s|del)\b|<h[12][^>]*>(?:(?!<\/h)[\s\S])*?line-through/i, (m, n) =>
  add("WARN", "tell-8", n, `strikethrough inside a headline — lead with the actual claim in plain language`));

// ── tell #9: lucide feature-card grid ────────────────────────────────────────
if (/lucide/i.test(src) && /grid-template-columns\s*:\s*repeat\(\s*[23]/i.test(src))
  add("INFO", "tell-9", 0, `lucide icons + 2/3-column card grid — the icon-feature-grid tell; show the product (screenshot, real output) instead`);

// ── tell #11: gradient buttons / glow halos ──────────────────────────────────
scan(/linear-gradient/i, (m, n, text) =>
  add(/btn|button|cta/i.test(text) ? "WARN" : "INFO", "tell-11", n,
    `linear-gradient — flat color reads less AI-made; HIGH if this is a button/CTA`));
scan(/box-shadow\s*:[^;]*\b(?:[2-9]\d|\d{3,})px[^;]*(?:oklch|rgb|#)[^;]*/i, (m, n) =>
  add("INFO", "tell-11", n, `large colored box-shadow — if it glows a button, drop it`));

// ── §3: meaning by color alone ───────────────────────────────────────────────
scan(/<(span|i)\s+[^>]*class="[^"]*\b(st|dot|status|lg|badge)\b[^"]*"[^>]*>\s*<\/\1>/i, (m, n) =>
  add("HIGH", "a11y-color", n, `empty colored glyph (.${m[2]}) — status carried by color alone; pair with a shape or text label (✓ shipped / ◐ partial / ○ open)`));

// ── tell #12: em-dash density ────────────────────────────────────────────────
const emDashes = (src.match(/—/g) ?? []).length;
const paras = (src.match(/<p[\s>]/g) ?? []).length || 1;
if (emDashes / paras > 0.6)
  add("WARN", "tell-12", 0, `${emDashes} em-dashes across ${paras} paragraphs — em-dash-heavy prose is a tell; cap at one per paragraph`);

// ── report (identical messages grouped: first line + count) ──────────────────
const order: Sev[] = ["HIGH", "WARN", "INFO"];
findings.sort((a, b) => order.indexOf(a.sev) - order.indexOf(b.sev) || a.line - b.line);
const groups = new Map<string, { sev: Sev; tag: string; msg: string; lines: number[] }>();
for (const f of findings) {
  const key = `${f.sev}|${f.tag}|${f.msg}`;
  const g = groups.get(key) ?? { sev: f.sev, tag: f.tag, msg: f.msg, lines: [] };
  if (f.line) g.lines.push(f.line);
  groups.set(key, g);
}
for (const g of groups.values()) {
  const where = g.lines.length === 0 ? "" : g.lines.length === 1 ? `line ${g.lines[0]}: ` : `lines ${g.lines.slice(0, 3).join(", ")}${g.lines.length > 3 ? ` +${g.lines.length - 3} more` : ""}: `;
  console.log(`${g.sev.padEnd(5)} [${g.tag}] ${where}${g.msg}`);
}

const high = findings.filter((f) => f.sev === "HIGH").length;
const warn = findings.filter((f) => f.sev === "WARN").length;
const tellTags = new Set(findings.filter((f) => f.tag.startsWith("tell-")).map((f) => f.tag));
console.log(`\nsummary: ${high} high, ${warn} warn, ${findings.length - high - warn} info · ${tellTags.size} distinct tells`);
if (tellTags.size >= 3)
  console.log(`3+ tells in combination reads as AI-made regardless of individual quality (design-core §6)`);
process.exit(strict && high > 0 ? 1 : 0);
