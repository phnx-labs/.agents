#!/usr/bin/env bun
// Comment composition — the signal the module graph can't see: where architecture
// prose is written as inline comment blocks instead of living in docs/.
//
// The module graph tells you how the code is coupled; it says nothing about the
// 12–30% of non-blank lines that are comments. Most of that is load-bearing and
// STAYS: per-symbol API docs (godoc/JSDoc on an exported name), and point-of-use
// gotchas / security invariants / ticket-anchored WHYs sitting on the line they
// explain. The relocatable part is the multi-line ARCHITECTURE ESSAY — a file-head
// or subsystem design narrative (data flow, storage model, protocol, isolation
// model, "why it's built this way") written as a comment block. That prose rots
// next to code, isn't discoverable, and inflates the ratio. The move it feeds is
// "lift the essay into docs/NN-<topic>.md, leave a pointer + the gotchas inline".
//
// This script derives, per module (a directory at --depth):
//   1. comment_pct        comment ÷ (code+comment) non-blank lines.
//   2. code_test_ratio    source LOC ÷ test LOC (lower = more test code; NOT a
//                         quality measure — a low ratio can hide skipped/dead tests).
//   3. essay_blocks       contiguous comment runs ≥ --min-block lines (default 15) —
//                         the relocate-to-docs candidates, with file:line + size.
//
// HEURISTIC, stated honestly: a big block is an essay CANDIDATE, not a verdict. A
// long per-symbol doc or a legitimately dense invariant can trip the threshold; the
// plan author reads each candidate and keeps point-of-use docs inline. Comment
// density is therefore NOT a target to minimize — it is a map to where design prose
// is mislocated. Reporting the candidates, never auto-cutting, is the whole contract.
//
// Languages: Go, TS/TSX, JS/JSX. Others counted in meta.skipped_files.
//
// Usage: bun comments.ts <run-dir> [--scope <path>] [--depth N] [--min-block N]

import { readFileSync, readdirSync, mkdirSync, statSync } from "node:fs";
import { join, relative, extname } from "node:path";

const args = process.argv.slice(2);
const runDir = args[0];
if (!runDir || runDir.startsWith("--")) {
  console.error("usage: comments.ts <run-dir> [--scope <path>] [--depth N] [--min-block N]");
  process.exit(1);
}
mkdirSync(runDir, { recursive: true });

let scope = ".";
let depth = 2;
let minBlock = 15;
for (let i = 1; i < args.length; i++) {
  if (args[i] === "--scope") scope = args[++i];
  else if (args[i] === "--depth") depth = Number(args[++i]) || 2;
  else if (args[i] === "--min-block") minBlock = Number(args[++i]) || 15;
}

const CODE_EXT = new Set([".go", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs"]);
const EXCLUDE = new Set([
  "node_modules", "dist", "build", "out", ".next", "vendor", "coverage",
  "testdata", ".git", ".agents",
]);

function isTest(path: string): boolean {
  const b = path.split("/").pop() || "";
  if (b.endsWith("_test.go")) return true;
  if (b.includes(".test.") || b.includes(".spec.")) return true;
  return path.split("/").some((p) => p === "__tests__" || p === "e2e" || p === "__mocks__");
}

// Classify each line; also collect contiguous comment runs (essay candidates).
// A blank line does NOT break a run — design blocks use blank comment lines — but
// a line of code does.
function scan(path: string) {
  let code = 0, comment = 0, inBlock = false;
  const blocks: { start: number; lines: number }[] = [];
  let run = 0, runStart = 0;
  let text = "";
  try { text = readFileSync(path, "utf8"); } catch { return { code, comment, blocks }; }
  const lines = text.split("\n");
  lines.forEach((line, idx) => {
    const s = line.trim();
    let isComment = false;
    if (inBlock) { isComment = true; comment++; if (s.includes("*/")) inBlock = false; }
    else if (s === "") { /* blank: neither code nor comment */ }
    else if (s.startsWith("//") || s.startsWith("#")) { isComment = true; comment++; }
    else if (s.startsWith("/*")) { isComment = true; comment++; if (!s.slice(2).includes("*/")) inBlock = true; }
    else if (s.startsWith("*")) { isComment = true; comment++; } // JSDoc continuation
    else { code++; }
    if (isComment) { if (run === 0) runStart = idx + 1; run++; }
    else if (s !== "") { if (run >= minBlock) blocks.push({ start: runStart, lines: run }); run = 0; }
  });
  if (run >= minBlock) blocks.push({ start: runStart, lines: run });
  return { code, comment, blocks };
}

function walk(dir: string, out: string[]) {
  let entries: string[];
  try { entries = readdirSync(dir); } catch { return; }
  for (const e of entries) {
    if (EXCLUDE.has(e) || e.startsWith(".")) continue;
    const p = join(dir, e);
    let st;
    try { st = statSync(p); } catch { continue; }
    if (st.isDirectory()) walk(p, out);
    else if (CODE_EXT.has(extname(e)) && !e.endsWith(".d.ts")) out.push(p);
  }
}

const root = scope === "." ? process.cwd() : scope;
const files: string[] = [];
walk(root, files);

type Mod = { code: number; comment: number; tcode: number; essays: { file: string; line: number; lines: number }[] };
const mods = new Map<string, Mod>();

for (const f of files) {
  const rel = relative(root, f);
  const seg = rel.split("/");
  const mod = seg.length <= depth ? (seg.slice(0, -1).join("/") || "(root)") : seg.slice(0, depth).join("/");
  if (!mods.has(mod)) mods.set(mod, { code: 0, comment: 0, tcode: 0, essays: [] });
  const m = mods.get(mod)!;
  const { code, comment, blocks } = scan(f);
  if (isTest(f)) { m.tcode += code; }
  else {
    m.code += code; m.comment += comment;
    for (const b of blocks) m.essays.push({ file: rel, line: b.start, lines: b.lines });
  }
}

const modules = [...mods.entries()]
  .map(([name, m]) => ({
    module: name,
    code: m.code,
    comment: m.comment,
    comment_pct: m.code + m.comment ? +(100 * m.comment / (m.code + m.comment)).toFixed(1) : 0,
    test_code: m.tcode,
    code_test_ratio: m.tcode ? +(m.code / m.tcode).toFixed(1) : null,
    essay_blocks: m.essays.length,
    essay_lines: m.essays.reduce((s, e) => s + e.lines, 0),
    top_essays: m.essays.sort((a, b) => b.lines - a.lines).slice(0, 8),
  }))
  .filter((m) => m.code >= 200)
  .sort((a, b) => b.essay_lines - a.essay_lines);

const totalEssayLines = modules.reduce((s, m) => s + m.essay_lines, 0);
const totalEssayBlocks = modules.reduce((s, m) => s + m.essay_blocks, 0);

console.log(JSON.stringify({
  meta: {
    scope, depth, min_block: minBlock, files: files.length,
    note: "comment_pct is a MAP, not a target. Only multi-line architecture essays (top_essays) relocate to docs/; per-symbol API docs and point-of-use gotchas stay inline. code_test_ratio low != good.",
  },
  totals: { essay_blocks: totalEssayBlocks, essay_lines: totalEssayLines },
  modules,
}, null, 2));
