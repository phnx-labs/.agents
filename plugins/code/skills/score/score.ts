#!/usr/bin/env bun

import { readFileSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";

const targetArg = process.argv[2] || process.cwd();
const repo = execFileSync("git", ["-C", targetArg, "rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
const output = process.argv[3];
const tracked = execFileSync("git", ["-C", repo, "ls-files"], { encoding: "utf8", maxBuffer: 1 << 28 })
  .split("\n").filter(Boolean);

const ignored = /(^|\/)(node_modules|vendor|dist|build|coverage|fixtures?|testdata|__snapshots__|\.agents)(\/|$)/;
const source = /\.(?:[cm]?[jt]sx?|py|go|rs|rb|java|kt|swift|cs|php|sh|bash|zsh)$/i;
const tests = /(^|\/)(?:tests?|__tests__)(\/|$)|\.(?:test|spec)\.[^.]+$/i;
const sourceFiles = tracked.filter((file) => source.test(file) && !tests.test(file) && !ignored.test(file));
const agentsFiles = tracked.filter((file) => /(^|\/)AGENTS\.md$/.test(file) && !ignored.test(file));
const dirs = new Set<string>(["."]);

for (const file of sourceFiles) {
  let dir = dirname(file);
  while (dir !== ".") {
    dirs.add(dir);
    dir = dirname(dir);
  }
}

const directCount = (dir: string) => sourceFiles.filter((file) => dirname(file) === dir).length;
const subtreeCount = (dir: string) => {
  const prefix = dir === "." ? "" : `${dir}/`;
  return sourceFiles.filter((file) => file.startsWith(prefix)).length;
};
const depthBelow = (dir: string) => {
  const baseDepth = dir === "." ? 0 : dir.split("/").length;
  const prefix = dir === "." ? "" : `${dir}/`;
  return sourceFiles
    .filter((file) => file.startsWith(prefix))
    .reduce((max, file) => Math.max(max, dirname(file).split("/").filter(Boolean).length - baseDepth), 0);
};
const immediateSourceChildren = (dir: string) => {
  const prefix = dir === "." ? "" : `${dir}/`;
  return new Set(sourceFiles
    .filter((file) => file.startsWith(prefix))
    .map((file) => file.slice(prefix.length).split("/")[0])
    .filter((part) => part && sourceFiles.some((file) => file.startsWith(`${prefix}${part}/`)))).size;
};

const today = new Date();
const architectureWords = /\b(architecture|module|boundary|depends|calls|owns|responsib|invariant|entry point|lives|flow|layer|registry|source of truth)\b/gi;
const imperativeLines = /^\s*(?:[-*]\s*)?(?:run|use|do|don't|never|always|install|create|edit|update|add|remove|make|ensure|verify|check|execute|invoke)\b/gim;

type Context = {
  path: string;
  directory: string;
  last_updated: string | null;
  age_days: number | null;
  stale: boolean;
  has_frontmatter: boolean;
  architecture_signals: number;
  imperative_lines: number;
  nonblank_lines: number;
  pointer_like: boolean;
};

const contexts: Context[] = agentsFiles.map((path) => {
  const text = readFileSync(join(repo, path), "utf8");
  const frontmatter = text.match(/^---\s*\n([\s\S]*?)\n---\s*(?:\n|$)/);
  const dateText = frontmatter?.[1].match(/^last-updated:\s*["']?(\d{4}-\d{2}-\d{2})["']?\s*$/m)?.[1] ?? null;
  const parsed = dateText ? new Date(`${dateText}T00:00:00Z`) : null;
  const age = parsed && !Number.isNaN(parsed.valueOf()) ? Math.floor((today.valueOf() - parsed.valueOf()) / 86_400_000) : null;
  const architectureSignals = [...text.matchAll(architectureWords)].length;
  const imperative = [...text.matchAll(imperativeLines)].length;
  const nonblank = text.split("\n").filter((line) => line.trim()).length;
  return {
    path,
    directory: dirname(path),
    last_updated: dateText,
    age_days: age,
    stale: age === null || age > 180,
    has_frontmatter: Boolean(frontmatter),
    architecture_signals: architectureSignals,
    imperative_lines: imperative,
    nonblank_lines: nonblank,
    pointer_like: architectureSignals >= 3 && imperative / Math.max(nonblank, 1) < 0.35,
  };
});

const contextByDir = new Map(contexts.map((item) => [item.directory, item]));
const coreDirectories = [...dirs]
  .map((path) => ({
    path,
    direct_source_files: directCount(path),
    subtree_source_files: subtreeCount(path),
    max_descendant_depth: depthBelow(path),
    immediate_source_children: immediateSourceChildren(path),
    agents: contextByDir.get(path) ?? null,
  }))
  .filter((item) => item.path !== "." && (item.direct_source_files >= 5 || (item.subtree_source_files >= 15 && item.immediate_source_children >= 2)))
  .sort((a, b) => b.subtree_source_files - a.subtree_source_files || a.path.localeCompare(b.path));

const flatDirectories = [...dirs]
  .map((path) => ({ path, direct_source_files: directCount(path), subtree_source_files: subtreeCount(path) }))
  .filter((item) => item.direct_source_files >= 20)
  .sort((a, b) => b.direct_source_files - a.direct_source_files || a.path.localeCompare(b.path));

const godFiles = sourceFiles.map((path) => {
  let lines = 0;
  try { lines = readFileSync(join(repo, path), "utf8").split("\n").length; } catch {}
  return { path, lines };
}).filter((item) => item.lines >= 800).sort((a, b) => b.lines - a.lines);

const deepUnfocused = [...dirs]
  .map((path) => ({
    path,
    direct_source_files: directCount(path),
    subtree_source_files: subtreeCount(path),
    max_descendant_depth: depthBelow(path),
  }))
  .filter((item) => item.path !== "." && item.max_descendant_depth >= 4 && item.subtree_source_files >= 20 && item.direct_source_files >= 5)
  .sort((a, b) => b.max_descendant_depth - a.max_descendant_depth || b.subtree_source_files - a.subtree_source_files);

const covered = coreDirectories.filter((item) => item.agents).length;
const goodContexts = contexts.filter((item) => !item.stale && item.pointer_like && item.has_frontmatter).length;
const coverageScore = coreDirectories.length ? Math.round(45 * covered / coreDirectories.length) : 45;
const qualityScore = contexts.length ? Math.round(25 * goodContexts / contexts.length) : 0;
const organizationPenalty = Math.min(30, flatDirectories.length * 5 + godFiles.length * 3 + deepUnfocused.length * 3);
const organizationScore = 30 - organizationPenalty;

const actions = [
  ...coreDirectories.filter((item) => !item.agents).map((item) => ({
    priority: 1000 + item.subtree_source_files,
    path: item.path,
    kind: "missing-agents",
    evidence: `${item.subtree_source_files} source files in subtree; no local AGENTS.md`,
    action: "Add an architectural pointer for this module boundary.",
  })),
  ...coreDirectories.filter((item) => item.agents && (item.agents.stale || !item.agents.pointer_like)).map((item) => ({
    priority: 800 + item.subtree_source_files,
    path: item.agents!.path,
    kind: item.agents!.stale ? "stale-agents" : "weak-agents",
    evidence: item.agents!.last_updated
      ? `last-updated ${item.agents!.last_updated}; ${item.subtree_source_files} source files in subtree`
      : `no valid last-updated date; ${item.subtree_source_files} source files in subtree`,
    action: "Keep module relationships and invariants; remove volatile procedure detail.",
  })),
  ...flatDirectories.map((item) => ({
    priority: 600 + item.direct_source_files,
    path: item.path,
    kind: "flat-directory",
    evidence: `${item.direct_source_files} direct source files`,
    action: "Group files by the domains already present after checking import boundaries.",
  })),
  ...godFiles.map((item) => ({
    priority: 400 + Math.floor(item.lines / 100),
    path: item.path,
    kind: "god-file",
    evidence: `${item.lines} lines`,
    action: "Separate cohesive responsibilities at existing call seams.",
  })),
  ...deepUnfocused.map((item) => ({
    priority: 200 + item.max_descendant_depth,
    path: item.path,
    kind: "deep-unfocused-tree",
    evidence: `${item.subtree_source_files} source files; ${item.max_descendant_depth} descendant levels; ${item.direct_source_files} direct files`,
    action: "Make the directory level express one architectural responsibility.",
  })),
].sort((a, b) => b.priority - a.priority || a.path.localeCompare(b.path));

const result = {
  generated_at: today.toISOString(),
  repository: repo,
  score: coverageScore + qualityScore + organizationScore,
  components: { agents_coverage: coverageScore, agents_quality: qualityScore, directory_organization: organizationScore },
  thresholds: { core_direct_files: 5, core_subtree_files: 15, stale_days: 180, flat_direct_files: 20, god_file_lines: 800, deep_descendant_levels: 4 },
  totals: { tracked_files: tracked.length, source_files: sourceFiles.length, agents_files: contexts.length, core_directories: coreDirectories.length },
  core_directories: coreDirectories,
  agents_files: contexts,
  flat_directories: flatDirectories,
  god_files: godFiles,
  deep_unfocused_trees: deepUnfocused,
  actions,
};

const json = `${JSON.stringify(result, null, 2)}\n`;
if (output) writeFileSync(resolve(output), json);
else process.stdout.write(json);
