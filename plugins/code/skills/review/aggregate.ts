#!/usr/bin/env bun
// Merges per-pass JSON findings into one sorted, deduped array.
// Usage: bun aggregate.ts <findings-dir>
// Outputs to stdout.

import { readdirSync, readFileSync, existsSync } from "node:fs";
import { join } from "node:path";

type Severity = "blocker" | "should" | "nice";
type Category = "architecture" | "code-health" | "context" | "patterns";

interface Finding {
  category: Category;
  severity: Severity;
  rule: string;
  file: string;
  line_start: number;
  line_end?: number;
  snippet?: string;
  anchor_file?: string | null;
  anchor_line?: number | null;
  anchor_snippet?: string | null;
  fix_one_line?: string;
  tool: string;
}

const SEVERITY_ORDER: Record<Severity, number> = { blocker: 0, should: 1, nice: 2 };

const findingsDir = process.argv[2];
if (!findingsDir || !existsSync(findingsDir)) {
  console.error(`aggregate.ts: findings dir not found: ${findingsDir}`);
  process.exit(1);
}

const all: Finding[] = [];
for (const f of readdirSync(findingsDir)) {
  if (!f.endsWith(".json")) continue;
  const raw = readFileSync(join(findingsDir, f), "utf8").trim();
  if (!raw) continue;
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (e) {
    // Try JSONL
    const lines = raw.split("\n").filter((l) => l.trim());
    parsed = lines.map((l) => JSON.parse(l));
  }
  if (!Array.isArray(parsed)) continue;
  for (const item of parsed) {
    if (item && typeof item === "object" && "category" in item && "severity" in item) {
      all.push(item as Finding);
    }
  }
}

// Dedupe on (file, line_start, rule, category).
const seen = new Set<string>();
const deduped: Finding[] = [];
for (const f of all) {
  const key = `${f.category}|${f.file}|${f.line_start}|${f.rule}`;
  if (seen.has(key)) continue;
  seen.add(key);
  deduped.push(f);
}

deduped.sort((a, b) => {
  const sev = SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity];
  if (sev !== 0) return sev;
  const cat = a.category.localeCompare(b.category);
  if (cat !== 0) return cat;
  const file = a.file.localeCompare(b.file);
  if (file !== 0) return file;
  return a.line_start - b.line_start;
});

process.stdout.write(JSON.stringify(deduped, null, 2) + "\n");
