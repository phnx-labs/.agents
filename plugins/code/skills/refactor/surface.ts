#!/usr/bin/env bun
// Surface census — how large is the thing a user (or an agent) has to search?
//
// Two modes, both emitting the same grading per entry:
//   --cli <bin>   walk `<bin> ... --help` recursively for every command path
//   --exports     list exported symbols from tracked source files
//
// Per entry: is it documented, is it tested, how many non-test references does it
// have, and when was its file last touched. An entry with no docs, no tests and no
// non-test reference is an ORPHAN CANDIDATE — not proof of death. In a codebase
// where commands resolve by NAME, static reachability proves nothing; the string
// search here is the check that matters, and it is still only a candidate list.
//
// Bounds: depth 4, 800 nodes, concurrency 8, 10s per help invocation. Hitting a
// bound is recorded in meta.truncated — a truncated census must be reported as
// truncated, never as the count.
//
// Usage: bun surface.ts <run-dir> [--cli <bin>] [--exports] [--depth N] [--max N]

import { readFileSync, mkdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join } from "node:path";

const args = process.argv.slice(2);
const runDir = args[0];
if (!runDir || runDir.startsWith("--")) {
  console.error("usage: surface.ts <run-dir> [--cli <bin>] [--exports] [--depth N] [--max N]");
  process.exit(1);
}
mkdirSync(runDir, { recursive: true });

let cli = "";
let doExports = false;
let maxDepth = 4;
let maxNodes = 800;
for (let i = 1; i < args.length; i++) {
  if (args[i] === "--cli") cli = args[++i];
  else if (args[i] === "--exports") doExports = true;
  else if (args[i] === "--depth") maxDepth = Number(args[++i]) || 4;
  else if (args[i] === "--max") maxNodes = Number(args[++i]) || 800;
}
if (!cli && !doExports) {
  console.error("surface.ts: pass --cli <bin> or --exports");
  process.exit(1);
}

const repoRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
const tracked = execFileSync("git", ["-C", repoRoot, "ls-files"], {
  encoding: "utf8",
  maxBuffer: 1 << 28,
}).split("\n").filter(Boolean);

const TEST_RE = /(^|\/)(tests?|__tests__|spec)\//i;
const TEST_FILE_RE = /\.(test|spec)\.[a-z]+$/i;
const isTest = (f: string) => TEST_RE.test(f) || TEST_FILE_RE.test(f);
const SOURCE_RE = /\.(ts|tsx|js|jsx|mjs|cjs|go|py|rs|rb|java|kt|swift|cs|sh|bash)$/;

const read = (f: string) => {
  try {
    return readFileSync(join(repoRoot, f), "utf8");
  } catch {
    return "";
  }
};

const docFiles = tracked.filter((f) => /\.(md|mdx|txt|rst)$/i.test(f));
const testFiles = tracked.filter((f) => isTest(f));
const srcFiles = tracked.filter((f) => SOURCE_RE.test(f) && !isTest(f));

const docCorpus = docFiles.map(read).join("\n").toLowerCase();
const testCorpus = testFiles.map(read).join("\n").toLowerCase();
// Read every source file ONCE. Re-reading per surface entry is O(entries x files)
// and turns a 30-second census into a 20-minute one on a 500-command CLI.
const srcTexts: { file: string; text: string }[] = srcFiles.map((f) => ({ file: f, text: read(f).toLowerCase() }));
const testTexts: string[] = testFiles.map((f) => read(f).toLowerCase());

const lastTouched = (f: string) => {
  try {
    return execFileSync("git", ["-C", repoRoot, "log", "-1", "--format=%cs", "--", f], {
      encoding: "utf8",
    }).trim() || null;
  } catch {
    return null;
  }
};

interface Entry {
  kind: "command" | "export";
  name: string;         // full command path, or symbol name
  depth: number;
  file: string | null;
  documented: boolean;
  tested: boolean;
  references: number;   // non-test, non-self references
  last_touched: string | null;
  orphan_candidate: boolean;
}

const truncated: string[] = [];
const entries: Entry[] = [];

// ------------------------------------------------------------------- CLI mode
if (cli) {
  const helpOf = async (path: string[]): Promise<string> => {
    const proc = Bun.spawn([cli, ...path, "--help"], { stdout: "pipe", stderr: "pipe" });
    const timer = setTimeout(() => proc.kill(), 10_000);
    const [out, err] = await Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
    ]);
    await proc.exited;
    clearTimeout(timer);
    return out || err; // some CLIs print help to stderr
  };

  // Two help dialects have to parse, or the census silently returns zero:
  //   1. commander's default `Commands:` block;
  //   2. hand-rolled grouped sections (`Agent versions:`, `Run and dispatch:`) —
  //      what a CLI that has outgrown the default help looks like, and exactly the
  //      case this skill exists for.
  // So: read indented `<name>  <description>` rows under ANY section except the
  // prose ones, where a bare `agents run …` example would masquerade as a command.
  // `Arguments:` matters as much as `Options:` — commander lists positional args in
  // the same indented shape as subcommands, so leaving it in invents commands that
  // do not exist (`sessions bookmark ids`) and reports them as orphans.
  const SKIP_SECTION = /^(usage|options|arguments?|examples?|notes?|quick start|environment|see also|aliases)\b/i;
  const parseCommands = (help: string): string[] => {
    const out = new Set<string>();
    let section = "";
    for (const line of help.split("\n")) {
      if (/^\S.*:\s*$/.test(line)) { section = line.trim(); continue; }
      if (/^\S/.test(line)) { section = ""; continue; }
      if (SKIP_SECTION.test(section)) continue;
      const m = line.match(/^\s{2,}([a-z][a-z0-9:_-]*)(?:\|[a-z0-9|_-]+)?(?:\s+[<[][^\s]*)*\s{2,}\S/);
      if (!m) continue;
      const name = m[1];
      if (name === "help" || name === cli) continue;
      out.add(name);
    }
    return [...out];
  };

  // A command that takes a dynamic name as its subcommand (`agents profile <name>`)
  // re-offers every sibling at each level, so a naive walk multiplies forever:
  // `profile glm glm`, `profile kimi glm`, … Two guards stop it, and the fact that
  // they are NEEDED is itself a finding worth reporting — an agent searching that
  // help is walking the same combinatorial tree.
  //
  // Both guards are ANCESTRY-scoped, never global. A global "have I seen this child
  // set before?" is wrong on exactly the CLIs this skill is built for: a well-shaped
  // surface reuses one verb vocabulary across groups on purpose, so `skills`,
  // `permissions`, and `subagents` all offer {add,list,remove,view} — and a global
  // check silently drops two of the three real groups, undercounting the census that
  // the shrink-the-surface move ranks on. A repeat only means recursion when it
  // repeats on the path from the root to THIS node.
  interface Node { path: string[]; ancestorSigs: Set<string> }
  const queue: Node[] = [{ path: [], ancestorSigs: new Set() }];
  let nodes = 0;
  let cycles = 0;
  while (queue.length) {
    const batch = queue.splice(0, 8);
    const results = await Promise.all(
      batch.map(async (node) => ({ node, help: await helpOf(node.path) })),
    );
    for (const { node, help } of results) {
      const { path, ancestorSigs } = node;
      const children = parseCommands(help);
      const sig = children.slice().sort().join(",");
      if (path.length > 0 && sig && ancestorSigs.has(sig)) { cycles++; continue; }
      const childSigs = sig ? new Set([...ancestorSigs, sig]) : ancestorSigs;
      for (const child of children) {
        if (path.includes(child)) { cycles++; continue; }
        if (nodes >= maxNodes) { queue.length = 0; break; }
        const full = [...path, child];
        nodes++;
        // Grade on the QUALIFIED invocation, never the bare leaf. A bare `add`
        // matches 586 files and grades every command as documented and referenced —
        // a census that says everything is fine is worse than no census.
        const invocation = `${cli} ${full.join(" ")}`.toLowerCase();
        const leaf = full[full.length - 1].toLowerCase();
        const quoted = [`"${leaf}"`, `'${leaf}'`];
        const file = srcFiles.find((f) => f.includes(`/${full[0]}.`)) ?? null;
        const refs = srcTexts.filter(
          (s) => s.text.includes(invocation) || (quoted.some((q) => s.text.includes(q)) && s.text.includes(full[0])),
        ).length;
        const documented = docCorpus.includes(invocation);
        const tested =
          testCorpus.includes(invocation) ||
          testTexts.some((x) => quoted.some((q) => x.includes(q)) && x.includes(full[0]));
        entries.push({
          kind: "command",
          name: full.join(" "),
          depth: full.length,
          file,
          documented,
          tested,
          references: refs,
          last_touched: file ? lastTouched(file) : null,
          orphan_candidate: !documented && !tested && refs <= 1,
        });
        if (full.length < maxDepth) queue.push({ path: full, ancestorSigs: childSigs });
      }
    }
  }
  if (nodes >= maxNodes) truncated.push(`census truncated at ${maxNodes} commands — count is a floor, not the total`);
  if (cycles) truncated.push(`${cycles} recursive/self-referential command paths skipped (a command whose subcommand set repeats its parent's — surface sprawl in its own right)`);
}

// --------------------------------------------------------------- exports mode
if (doExports) {
  // One pass: extract exported symbols per file AND build a token→files index, so
  // reference counting is a map lookup instead of N greps.
  const EXPORT_RE =
    /^\s*export\s+(?:default\s+)?(?:async\s+)?(?:function|const|let|class|interface|type|enum)\s+([A-Za-z_$][\w$]*)/gm;
  const TOKEN_RE = /[A-Za-z_$][\w$]*/g;

  const exportsOf = new Map<string, string[]>();
  const tokenFiles = new Map<string, Set<string>>();
  const scanned = [...srcFiles, ...testFiles].filter((f) => /\.(ts|tsx|js|jsx|mjs|cjs)$/.test(f));

  for (const f of scanned) {
    const text = read(f);
    if (!text) continue;
    if (!isTest(f)) {
      const names: string[] = [];
      for (const m of text.matchAll(EXPORT_RE)) names.push(m[1]);
      if (names.length) exportsOf.set(f, names);
    }
    for (const m of text.matchAll(TOKEN_RE)) {
      let s = tokenFiles.get(m[0]);
      if (!s) tokenFiles.set(m[0], (s = new Set()));
      s.add(f);
    }
  }

  for (const [f, names] of exportsOf) {
    for (const name of names) {
      const users = tokenFiles.get(name) ?? new Set<string>();
      const nonSelf = [...users].filter((u) => u !== f);
      const nonTest = nonSelf.filter((u) => !isTest(u));
      const lower = name.toLowerCase();
      entries.push({
        kind: "export",
        name,
        depth: 0,
        file: f,
        documented: docCorpus.includes(lower),
        tested: nonSelf.length !== nonTest.length,
        references: nonTest.length,
        last_touched: null,
        orphan_candidate: nonTest.length === 0 && nonSelf.length === 0 && !docCorpus.includes(lower),
      });
    }
  }
}

const commands = entries.filter((e) => e.kind === "command");
const exportsList = entries.filter((e) => e.kind === "export");

console.log(
  JSON.stringify(
    {
      meta: {
        repo: repoRoot,
        cli: cli || null,
        command_count: commands.length,
        top_level_commands: commands.filter((e) => e.depth === 1).length,
        max_depth_seen: commands.reduce((m, e) => Math.max(m, e.depth), 0),
        export_count: exportsList.length,
        undocumented: entries.filter((e) => !e.documented).length,
        untested: entries.filter((e) => !e.tested).length,
        orphan_candidates: entries.filter((e) => e.orphan_candidate).length,
        truncated,
        caveat:
          "orphan_candidate is a CANDIDATE list. Names resolved dynamically (CLI lookup, registries, reflection) and consumers in other repos are invisible here — grep the string across companion repos before deleting anything.",
      },
      entries: entries.sort((a, b) => Number(b.orphan_candidate) - Number(a.orphan_candidate) || a.name.localeCompare(b.name)),
    },
    null,
    2,
  ),
);
