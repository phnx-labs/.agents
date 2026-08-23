import { afterEach, describe, expect, test } from "bun:test";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join } from "node:path";

const fixture = join(import.meta.dir, "testdata", "repo");
const scorer = join(import.meta.dir, "score.ts");

afterEach(() => rmSync(fixture, { recursive: true, force: true }));

describe("code:score census", () => {
  test("scores local AGENTS.md coverage and flat directories from tracked files", () => {
    mkdirSync(join(fixture, "src", "core"), { recursive: true });
    execFileSync("git", ["init", "-q", fixture]);
    writeFileSync(join(fixture, "AGENTS.md"), "# Repository architecture\nModules call the core registry.\n");
    for (let i = 0; i < 20; i++) writeFileSync(join(fixture, "src", "core", `file-${i}.ts`), `export const value${i} = ${i};\n`);
    execFileSync("git", ["-C", fixture, "add", "."]);

    const result = JSON.parse(execFileSync("bun", [scorer, fixture], { encoding: "utf8" }));
    const core = result.core_directories.find((item: { path: string }) => item.path === "src/core");

    expect(core.direct_source_files).toBe(20);
    expect(core.agents).toBeNull();
    expect(result.flat_directories[0]).toEqual(expect.objectContaining({ path: "src/core", direct_source_files: 20 }));
    expect(result.actions[0]).toEqual(expect.objectContaining({ path: "src/core", kind: "missing-agents" }));
  });

  test("accepts a current pointer-like AGENTS.md with last-updated frontmatter", () => {
    mkdirSync(join(fixture, "lib"), { recursive: true });
    execFileSync("git", ["init", "-q", fixture]);
    writeFileSync(join(fixture, "lib", "AGENTS.md"), "---\nlast-updated: 2026-08-23\n---\n# Architecture\nThis module owns the registry. Callers enter through index.ts. The invariant is one owner.\n");
    for (let i = 0; i < 5; i++) writeFileSync(join(fixture, "lib", `part-${i}.ts`), `export const part${i} = ${i};\n`);
    execFileSync("git", ["-C", fixture, "add", "."]);

    const result = JSON.parse(execFileSync("bun", [scorer, fixture], { encoding: "utf8" }));
    const context = result.agents_files.find((item: { path: string }) => item.path === "lib/AGENTS.md");

    expect(context).toEqual(expect.objectContaining({ has_frontmatter: true, stale: false, pointer_like: true }));
    expect(result.components.agents_coverage).toBe(45);
    expect(result.components.agents_quality).toBe(25);
  });
});
