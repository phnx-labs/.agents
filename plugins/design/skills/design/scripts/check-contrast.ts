#!/usr/bin/env bun
// WCAG 2.x contrast checker. Computes real ratios so no agent ever guesses one
// (design-core §3: "State the ratio; do not guess it").
//
// Usage:
//   bun check-contrast.ts <fg> <bg> [--large]
//   bun check-contrast.ts --json '[{"fg":"#111","bg":"#fafafa","label":"body","large":false}, ...]'
//
// Colors: #rgb / #rrggbb / #rrggbbaa, rgb()/rgba(), oklch(L C H [/ A]).
// A translucent fg is composited over the bg before measuring (matches what
// the eye sees). Exit 0 = all pass AA; exit 1 = at least one failure.

type RGB = { r: number; g: number; b: number; a: number }; // linear-light 0..1

function srgbToLinear(c: number): number {
  return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

function parseHex(s: string): RGB | null {
  const m = s.match(/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i);
  if (!m) return null;
  let h = m[1];
  if (h.length === 3) h = h.split("").map((c) => c + c).join("");
  const n = (i: number) => parseInt(h.slice(i, i + 2), 16) / 255;
  return { r: srgbToLinear(n(0)), g: srgbToLinear(n(2)), b: srgbToLinear(n(4)), a: h.length === 8 ? n(6) : 1 };
}

function parseRgbFunc(s: string): RGB | null {
  const m = s.match(/^rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:[,\s/]+([\d.%]+))?\s*\)$/i);
  if (!m) return null;
  const a = m[4] ? (m[4].endsWith("%") ? parseFloat(m[4]) / 100 : parseFloat(m[4])) : 1;
  return {
    r: srgbToLinear(Math.min(255, parseFloat(m[1])) / 255),
    g: srgbToLinear(Math.min(255, parseFloat(m[2])) / 255),
    b: srgbToLinear(Math.min(255, parseFloat(m[3])) / 255),
    a,
  };
}

// oklch(L C H [/ A]) → linear sRGB, via OKLab (Björn Ottosson's matrices).
function parseOklch(s: string): RGB | null {
  const m = s.match(/^oklch\(\s*([\d.]+%?)\s+([\d.]+)\s+([\d.]+)(?:deg)?\s*(?:\/\s*([\d.%]+))?\s*\)$/i);
  if (!m) return null;
  const L = m[1].endsWith("%") ? parseFloat(m[1]) / 100 : parseFloat(m[1]);
  const C = parseFloat(m[2]);
  const H = (parseFloat(m[3]) * Math.PI) / 180;
  const alpha = m[4] ? (m[4].endsWith("%") ? parseFloat(m[4]) / 100 : parseFloat(m[4])) : 1;
  const a = C * Math.cos(H);
  const b = C * Math.sin(H);
  const l_ = L + 0.3963377774 * a + 0.2158037573 * b;
  const m_ = L - 0.1055613458 * a - 0.0638541728 * b;
  const s_ = L - 0.0894841775 * a - 1.291485548 * b;
  const l3 = l_ ** 3, m3 = m_ ** 3, s3 = s_ ** 3;
  const clamp = (v: number) => Math.min(1, Math.max(0, v));
  return {
    r: clamp(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3),
    g: clamp(-1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3),
    b: clamp(-0.0041960863 * l3 - 0.7034186147 * m3 + 1.707614701 * s3),
    a: alpha,
  };
}

function parseColor(s: string): RGB | null {
  const t = s.trim();
  return parseHex(t) ?? parseRgbFunc(t) ?? parseOklch(t);
}

function composite(fg: RGB, bg: RGB): RGB {
  if (fg.a >= 1) return fg;
  const a = fg.a;
  return { r: fg.r * a + bg.r * (1 - a), g: fg.g * a + bg.g * (1 - a), b: fg.b * a + bg.b * (1 - a), a: 1 };
}

function luminance(c: RGB): number {
  return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
}

function ratio(fg: RGB, bg: RGB): number {
  const lf = luminance(composite(fg, bg));
  const lb = luminance(bg);
  const [hi, lo] = lf > lb ? [lf, lb] : [lb, lf];
  return (hi + 0.05) / (lo + 0.05);
}

interface Pair { fg: string; bg: string; label?: string; large?: boolean }

function check(p: Pair): { line: string; pass: boolean } {
  const fg = parseColor(p.fg);
  const bg = parseColor(p.bg);
  if (!fg || !bg) return { line: `ERROR  cannot parse ${!fg ? p.fg : p.bg}`, pass: false };
  const r = ratio(fg, bg);
  const need = p.large ? 3.0 : 4.5;
  const aaa = p.large ? 4.5 : 7.0;
  const verdict = r >= aaa ? "AAA" : r >= need ? "AA" : "FAIL";
  const label = p.label ? ` [${p.label}]` : "";
  return {
    line: `${verdict.padEnd(5)} ${r.toFixed(2)}:1  ${p.fg} on ${p.bg}${label}${p.large ? " (large text, needs 3.0)" : " (needs 4.5)"}`,
    pass: r >= need,
  };
}

const args = process.argv.slice(2);
let pairs: Pair[];
if (args[0] === "--json") {
  pairs = JSON.parse(args[1] ?? "[]");
} else if (args.length >= 2) {
  pairs = [{ fg: args[0], bg: args[1], large: args.includes("--large") }];
} else {
  console.error("usage: check-contrast.ts <fg> <bg> [--large] | --json '[{fg,bg,label?,large?}]'");
  process.exit(2);
}

let allPass = true;
for (const p of pairs) {
  const { line, pass } = check(p);
  console.log(line);
  if (!pass) allPass = false;
}
process.exit(allPass ? 0 : 1);
