#!/usr/bin/env bun
// Pattern fit — is a concept following the shape it should, or is it a pile of arms?
//
// The move this feeds is "give the concept a contract": a family of variants that a
// codebase dispatches on by NAME (`if (agent === 'claude') … else if (agent ===
// 'codex') …`) almost always wants the provider pattern instead — one declared
// contract plus one implementation per variant, registered in a table. Every language
// spells the contract differently (Go interface, TS interface / discriminated union,
// Python Protocol or ABC, Rust trait, Java/C# interface, Swift protocol) but the shape
// and the payoff are identical: adding a variant becomes one new file plus one table
// entry, and the type system tells you what is missing instead of a reviewer noticing
// that three call sites were never updated.
//
// What this finds, per discriminator family:
//   members          the variant names the code actually branches on
//   arms             how many if/=== or case sites exist (what collapses)
//   has_contract     an interface / union type / ABC naming those members
//   has_registry     a table or map keyed by those members
//   provider_dir     a directory with one file per member (the implementation set)
//   capability_holes for a provider dir: members missing an export its siblings have
//                    — the "wired up three harnesses and skipped the rest" defect
//   verdict          exemplar | partial | missing
//
// An `exemplar` family in the SAME repo is the most valuable output here: it is the
// pattern this codebase already chose, so the fix for a `missing` family is "look like
// that one", not "adopt an abstraction from a book."
//
// Languages: TS/JS, Go, Python. Others are counted in meta.unparsed_files.
// This is a CANDIDATE detector. A family of variants that genuinely diverge in
// contract is not a provider family — the skill requires a human/agent judgement call
// before any move, and `same_contract: null` marks that judgement as not yet made.
//
// Usage: bun patterns.ts <run-dir> [--scope <path>] [--min-members N] [--min-arms N]

import { readFileSync, mkdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join, dirname, basename, extname } from "node:path";

const args = process.argv.slice(2);
const runDir = args[0];
if (!runDir || runDir.startsWith("--")) {
  console.error("usage: patterns.ts <run-dir> [--scope <path>] [--min-members N] [--min-arms N]");
  process.exit(1);
}
mkdirSync(runDir, { recursive: true });

let scope = "";
let minMembers = 3;
let minArms = 4;
for (let i = 1; i < args.length; i++) {
  if (args[i] === "--scope") scope = args[++i];
  else if (args[i] === "--min-members") minMembers = Number(args[++i]) || 3;
  else if (args[i] === "--min-arms") minArms = Number(args[++i]) || 4;
}

const repoRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
const tracked = execFileSync("git", ["-C", repoRoot, "ls-files", "--", scope || "."], {
  encoding: "utf8",
  maxBuffer: 1 << 28,
}).split("\n").filter(Boolean);

const TEST_RE = /(^|\/)(tests?|__tests__|spec)\/|\.(test|spec)\.[a-z]+$/i;
const CODE = /\.(ts|tsx|js|jsx|mjs|cjs|go|py)$/;
const files = tracked.filter((f) => CODE.test(f) && !TEST_RE.test(f));
const unparsed = tracked.filter((f) => !CODE.test(f) && !TEST_RE.test(f)).length;

const read = (f: string) => {
  try {
    return readFileSync(join(repoRoot, f), "utf8");
  } catch {
    return "";
  }
};
const texts = new Map<string, string>();
for (const f of files) {
  const t = read(f);
  if (t) texts.set(f, t);
}

// ------------------------------------------------------------------- dispatch arms
// `x === 'lit'` / `x == "lit"` (TS/JS/Python) and `case "lit":` attributed to the
// nearest enclosing `switch (x)` / Go `switch x {`.
const EQ = /\b([A-Za-z_$][\w$.]*)\s*(?:===|==)\s*['"]([\w:@./-]+)['"]/g;
const EQ_REV = /['"]([\w:@./-]+)['"]\s*(?:===|==)\s*\b([A-Za-z_$][\w$.]*)/g;
const SWITCH = /\bswitch\s*\(?\s*([A-Za-z_$][\w$.]*)/;
const CASE = /^\s*case\s+['"]([\w:@./-]+)['"]\s*:/;

interface Site { file: string; arms: number }
interface Family {
  discriminator: string;
  members: Set<string>;
  sites: Map<string, number>;
  arms: number;
}
const families = new Map<string, Family>();

const bump = (disc: string, member: string, file: string) => {
  // strip a receiver: `opts.agent` and `agent` are the same discriminator
  const key = disc.split(".").pop()!;
  if (key.length < 3) return;
  // typeof rejection happens at the call site, where the line is available — a value
  // blocklist here would also discard legitimate variants (a CDP wait-condition union
  // really does have a `function` member).
  let fam = families.get(key);
  if (!fam) families.set(key, (fam = { discriminator: key, members: new Set(), sites: new Map(), arms: 0 }));
  fam.members.add(member);
  fam.sites.set(file, (fam.sites.get(file) ?? 0) + 1);
  fam.arms++;
};

for (const [f, text] of texts) {
  // `typeof p.head === 'string'` is a type guard, not a variant dispatch: left in, it
  // invents a member ('string') and can manufacture a whole family. Scan back to the line
  // start rather than a fixed width, so a cast between `typeof` and the comparison — and
  // the reversed form — are both covered.
  const guarded = (idx: number) => {
    const lineStart = text.lastIndexOf("\n", idx) + 1;
    return /\btypeof\b/.test(text.slice(lineStart, idx));
  };
  for (const m of text.matchAll(EQ)) {
    if (guarded(m.index!)) continue;
    bump(m[1], m[2], f);
  }
  for (const m of text.matchAll(EQ_REV)) {
    if (guarded(m.index!)) continue;
    bump(m[2], m[1], f);
  }

  let current = "";
  for (const line of text.split("\n")) {
    const sw = line.match(SWITCH);
    if (sw) { current = sw[1]; continue; }
    const c = line.match(CASE);
    if (c && current) bump(current, c[1], f);
  }
}

// ------------------------------------------------------------ contract and registry
// Precision matters more than recall here. An earlier cut fell back to "the first
// interface in the first file" and graded every family `exemplar` while pointing at
// an unrelated `interface NpmPackageMetadata` — a detector that says everything is
// fine is worse than no detector. Both checks below therefore require the MEMBERS
// themselves, or a type name that echoes the discriminator. No blind fallback.

const nameRelates = (name: string, disc: string) => {
  if (name.toLowerCase() === disc.toLowerCase()) return true;
  if (disc.length < 3) return false;
  // The real test is a CASE BOUNDARY in the original identifier, not a length ratio:
  // `TerminalBackend` ~ `backend` and `AgentId` ~ `agent` are compounds; `headroom` ~
  // `head` is one word that merely starts with another. A ratio gate got this backwards,
  // rejecting TerminalBackend while a bare substring test accepted headroom.
  const Cap = disc[0].toUpperCase() + disc.slice(1).toLowerCase();
  if (name.endsWith(Cap)) return true;                       // TerminalBackend / Backend
  if (name.startsWith(Cap)) {                                 // AgentId, AgentType
    const next = name[Cap.length];
    return next === undefined || next === next.toUpperCase();
  }
  return false;
};

const quoted = (m: string) => [`'${m}'`, `"${m}"`, `\`${m}\``];

// A contract names the members (union / enum / Literal) or is a type whose NAME echoes
// the discriminator and which is used as a key type (`Record<AgentId, …>`).
const contractFor = (disc: string, members: Set<string>) => {
  const list = [...members];
  const need = Math.max(2, Math.ceil(list.length * 0.5));
  for (const [f, text] of texts) {
    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
      if (!/\b(type|enum)\s+\w+|Literal\[/.test(lines[i])) continue;
      const window = lines.slice(i, i + 10).join(" ");
      const hits = list.filter((m) => quoted(m).some((q) => window.includes(q))).length;
      if (hits >= need) return { ref: `${f}:${i + 1}`, kind: "union" as const, covers: hits, of: list.length };
    }
  }
  // A named key type used in a Record/map position, e.g. `Record<AgentId, …>`.
  for (const [f, text] of texts) {
    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
      const m = lines[i].match(/Record<\s*([A-Za-z_$][\w$]*)\s*,/);
      if (m && nameRelates(m[1], disc)) {
        return { ref: `${f}:${i + 1}`, kind: "keyed-type" as const, covers: 0, of: list.length };
      }
    }
  }
  return null;
};

// A registry is a table keyed by the members, or a Record<> keyed by the contract type.
const registryFor = (disc: string, members: Set<string>) => {
  const list = [...members];
  const need = Math.max(2, Math.ceil(list.length * 0.5));
  let best: { ref: string; keys: number; of: number } | null = null;
  for (const [f, text] of texts) {
    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
      if (!/[:=]\s*\{|Record<|Map</.test(lines[i])) continue;
      const window = lines.slice(i, i + 40);
      let keyHits = 0;
      for (const m of list) {
        const re = new RegExp(`^\\s*(?:['"\`])?${m.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?:['"\`])?\\s*:`);
        if (window.some((l) => re.test(l))) keyHits++;
      }
      if (keyHits >= need && keyHits > (best?.keys ?? 0)) best = { ref: `${f}:${i + 1}`, keys: keyHits, of: list.length };
    }
  }
  if (best) return best;
  // Only if no real table enumerates the members: fall back to a `Record<Type, …>`
  // ANNOTATION. Citing an annotation when a table exists sends the agent to a type
  // declaration instead of the dispatch table it is supposed to route call sites
  // through — the citation has to be the thing you would actually edit.
  for (const [f, text] of texts) {
    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
      const rec = lines[i].match(/Record<\s*([A-Za-z_$][\w$]*)\s*,/);
      if (rec && nameRelates(rec[1], disc)) return { ref: `${f}:${i + 1}`, keys: 0, of: list.length };
    }
  }
  return null;
};

// A provider dir: >=2 member names appear as FILENAMES in one directory.
const providerDirFor = (members: Set<string>) => {
  const byDir = new Map<string, Set<string>>();
  for (const f of files) {
    const base = basename(f, extname(f));
    for (const m of members) {
      if (base === m || base === `${m}-agent` || base === `${m}_agent`) {
        const d = dirname(f);
        (byDir.get(d) ?? byDir.set(d, new Set()).get(d)!).add(m);
      }
    }
  }
  let best: { dir: string; covered: string[] } | null = null;
  for (const [d, ms] of byDir) if (!best || ms.size > best.covered.length) best = { dir: d, covered: [...ms] };
  return best && best.covered.length >= 2 ? best : null;
};

// Capability holes: for a provider dir, which exported names do siblings have that a
// member lacks. This is the "wired up three variants and silently skipped the rest"
// defect, made visible as a matrix instead of found by a reviewer.
// `export` is REQUIRED for TS/JS. Optional, it swept up every local `const` inside a
// function body and reported names like `result`, `parsed`, `raw` as missing
// capabilities — noise that drowned the real parity gaps.
const EXPORTED = /^\s*export\s+(?:async\s+)?(?:function|const|class)\s+([A-Za-z_$][\w$]*)|^\s*func\s+(?:\([^)]*\)\s*)?([A-Z][\w]*)\s*\(|^\s*def\s+([a-z_][\w]*)/gm;
const capabilityMatrix = (dir: string, covered: string[]) => {
  const perMember = new Map<string, Set<string>>();
  for (const m of covered) {
    const f = files.find((x) => dirname(x) === dir && basename(x, extname(x)).startsWith(m));
    if (!f) continue;
    const names = new Set<string>();
    for (const mm of (texts.get(f) ?? "").matchAll(EXPORTED)) names.add(mm[1] || mm[2] || mm[3]);
    perMember.set(m, names);
  }
  const all = new Map<string, number>();
  for (const names of perMember.values()) for (const n of names) all.set(n, (all.get(n) ?? 0) + 1);
  // a capability the MAJORITY implement is the de-facto contract; a member missing one
  // is the parity gap this repo's reviewer already looks for by hand.
  const majority = [...all].filter(([, c]) => c >= Math.ceil(perMember.size / 2) && c < perMember.size).map(([n]) => n);
  const holes: { member: string; missing: string[] }[] = [];
  for (const [m, names] of perMember) {
    const missing = majority.filter((n) => !names.has(n));
    if (missing.length) holes.push({ member: m, missing });
  }
  return { members: [...perMember.keys()], holes };
};

// ------------------------------------------------------------------------- assemble
const NOISE = /^(type|kind|mode|status|state|name|key|id|value|event|level|action|op|cmd|format|target|source|dir)$/;

// A generic discriminator name (`kind`, `mode`, `type`) is usually noise — but not
// always: `p.kind === 'local'` was a real dispatch that an outright exclusion dropped on
// the floor. Hold generic names to a higher bar rather than discarding them, and mark
// them so a reader knows the name alone did not earn the row.
const rows = [...families.values()]
  .filter((f) => {
    const generic = NOISE.test(f.discriminator);
    const memberBar = generic ? minMembers + 2 : minMembers;
    const armBar = generic ? minArms * 2 : minArms;
    return f.members.size >= memberBar && f.arms >= armBar;
  })
  .map((f) => {
    const contract = contractFor(f.discriminator, f.members);
    const registry = registryFor(f.discriminator, f.members);
    const provider = providerDirFor(f.members);
    const matrix = provider ? capabilityMatrix(provider.dir, provider.covered) : null;
    // arms per member is the bypass signal: a healthy provider family branches on the
    // name a handful of times (the dispatch itself); 236 arms over 21 members means
    // the table exists and the codebase is routing around it.
    const armsPerMember = f.arms / f.members.size;
    const verdict =
      !contract && !registry
        ? "missing"                                   // nothing to route through — introduce it
        : contract && registry && armsPerMember > 3
          ? "bypassed"                                // BOTH exist and call sites ignore them
          // Threshold read off the data, not guessed: on a real codebase the genuine
          // provider families cluster at 0.31-0.50 provider coverage (context .50,
          // platform .40, backend .36, agentType .33, detected .31) and the generic
          // grab-bags sit an order below (kind .12, action .11, mode .09, type .07).
          // 0.3 + a non-generic name separates them cleanly.
          : contract && registry && provider && (provider.covered.length / f.members.size) >= 0.3 && !NOISE.test(f.discriminator)
            ? "exemplar"                              // the shape this repo already chose
            : "partial";                              // one of the pair is missing — complete it
    return {
      discriminator: f.discriminator,
      generic_name: NOISE.test(f.discriminator),
      members: [...f.members].sort(),
      member_count: f.members.size,
      arms: f.arms,
      files: f.sites.size,
      top_sites: [...f.sites].sort((a, b) => b[1] - a[1]).slice(0, 8).map(([file, arms]) => ({ file, arms })),
      arms_by_area: (() => {
        // Arms grouped by their top two path segments. A family whose arms are spread
        // across unrelated areas is probably TWO concepts sharing a variable name — the
        // terminal `backend` and the secrets `backend` merge into one row otherwise.
        const areas = new Map<string, number>();
        for (const [file, arms] of f.sites) {
          const area = file.split("/").slice(0, -1).join("/");
          areas.set(area, (areas.get(area) ?? 0) + arms);
        }
        return [...areas].sort((a, b) => b[1] - a[1]).slice(0, 5).map(([area, arms]) => ({ area, arms }));
      })(),
      area_concentration: (() => {
        const areas = new Map<string, number>();
        for (const [file, arms] of f.sites) {
          const area = file.split("/").slice(0, -1).join("/");
          areas.set(area, (areas.get(area) ?? 0) + arms);
        }
        const top = Math.max(0, ...areas.values());
        return f.arms ? Number((top / f.arms).toFixed(2)) : 0;
      })(),
      has_contract: !!contract,
      contract_ref: contract?.ref ?? null,
      contract_kind: contract?.kind ?? null,
      has_registry: !!registry,
      registry_ref: registry?.ref ?? null,
      provider_dir: provider?.dir ?? null,
      provider_covered: provider?.covered ?? null,
      provider_coverage: provider ? Number((provider.covered.length / f.members.size).toFixed(2)) : null,
      capability_holes: matrix?.holes ?? null,
      arms_per_member: Number((f.arms / f.members.size).toFixed(1)),
      same_contract: null, // requires judgement — set by the skill, never by this script
      verdict,
    };
  })
  .sort((a, b) => b.arms - a.arms);

const exemplars = rows.filter((r) => r.verdict === "exemplar");
const missing = rows.filter((r) => r.verdict === "missing");
const bypassed = rows.filter((r) => r.verdict === "bypassed");

console.log(
  JSON.stringify(
    {
      meta: {
        repo: repoRoot,
        scope: scope || ".",
        files_scanned: texts.size,
        files_unparsed: unparsed,
        families: rows.length,
        exemplars: exemplars.length,
        partial: rows.filter((r) => r.verdict === "partial").length,
        bypassed: bypassed.length,
        missing: missing.length,
        collapsible_arms: [...bypassed, ...missing].reduce((s, r) => s + r.arms, 0),
        thresholds: { min_members: minMembers, min_arms: minArms },
        caveats: [
          "CANDIDATES, not verdicts. A family whose variants genuinely diverge in contract is not a provider family; `same_contract` stays null until an agent or human judges it.",
          "Detection is textual: a discriminator reached only through a helper (`isClaude(x)`) or a table lookup is invisible here.",
          "An `exemplar` in this repo is the pattern the codebase already chose — prefer it over any external pattern when proposing a fix.",
          "Families are keyed by VARIABLE NAME, so two unrelated concepts that share one (a terminal `backend` and a secrets `backend`) merge into a single polluted row. Check `top_sites` before trusting a member list.",
          "`capability_holes` compares exported names only; a capability reached through a shared base class, or one whose implementation differs in name, is invisible. Treat holes as candidates.",
          "`generic_name: true` marks a discriminator whose name alone (kind/mode/type) is weak evidence — it cleared a higher member and arm bar to appear at all.",
        ],
      },
      families: rows,
    },
    null,
    2,
  ),
);
