import { afterAll, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { filterPreviousSessions, filterSessions, safeString, sessionComparison, type SessionRow } from "./collect";

const scratch = await mkdtemp(join(tmpdir(), "yc-workweave-"));
afterAll(() => rm(scratch, { recursive: true, force: true }));

describe("workweave collector", () => {
  test("redacts absolute home paths on every supported desktop platform", () => {
    expect(safeString("/home/alice/project/report.json")).toBe("~/project/report.json");
    expect(safeString("/Users/Alice/project/report.json")).toBe("~/project/report.json");
    expect(safeString("C:\\Users\\Alice\\project\\report.json")).toBe("~\\project\\report.json");
    expect(safeString("D:/Users/Alice/project/report.json")).toBe("~/project/report.json");
  });

  test("excludes out-of-window rows from report metrics while retaining the census", () => {
    const now = Date.parse("2026-08-25T12:00:00Z");
    const rows = [
      { timestamp: "2026-08-24T12:00:00Z", outputTokens: 10 },
      { timestamp: "2026-07-24T12:00:00Z", outputTokens: 5 },
      { timestamp: "2026-06-01T12:00:00Z", outputTokens: 20 },
    ] as SessionRow[];
    expect(filterSessions(rows, "30d", now)).toEqual([rows[0]]);
    expect(filterSessions(rows, "all", now)).toEqual(rows);
    expect(filterPreviousSessions(rows, "30d", now)).toEqual([rows[1]]);
    expect(filterPreviousSessions(rows, "all", now)).toEqual([]);
    expect(sessionComparison([rows[0]], [rows[1]])).toMatchObject({
      current: { sessions: 1, outputTokens: 10 },
      previous: { sessions: 1, outputTokens: 5 },
      deltaPercent: { sessions: 0, outputTokens: 100 },
    });
  });

  test("collects the installed agents-cli's real local analytics flow", async () => {
    const output = join(scratch, "data.json");
    const process = Bun.spawn([
      "bun", join(import.meta.dir, "collect.ts"),
      "--project", "agents-cli", "--out", output,
    ], { cwd: join(import.meta.dir, "../../../../.."), stdout: "pipe", stderr: "pipe" });
    const [stderr, exitCode] = await Promise.all([
      new Response(process.stderr).text(),
      process.exited,
    ]);

    expect(exitCode, stderr).toBe(0);
    const report = JSON.parse(await readFile(output, "utf8"));
    expect(report.scope).toMatchObject({ project: "agents-cli", window: "30d", days: 30, sessionCensus: "all-paginated" });
    expect(Array.isArray(report.sources.sessions)).toBe(true);
    expect(report.sources.sessions.length).toBeGreaterThan(0);
    expect(Array.isArray(report.sources.hooks)).toBe(true);
    expect(report.sources.sessionMetrics.totals.sessions).toBe(report.scope.windowSessionCount);
    expect(report.sources.sessionComparison.current).toEqual(report.sources.sessionMetrics.totals);
    expect(report.sources.sessionComparison.previous).toHaveProperty("sessions");
    expect(report.sources.sessionComparison.deltaPercent).toHaveProperty("outputTokens");
    expect(report.scope.windowSessionCount).toBeLessThanOrEqual(report.scope.sessionCensusCount);
    expect(report.gaps.harnessMix).toBeUndefined();
    expect(report.gaps.modelMix).toBeUndefined();
    expect(report.gaps.sessions).toBeUndefined();
    const serialized = JSON.stringify(report.sources.sessions);
    for (const forbidden of ["filePath", "cwd", "account", "machine", "topic", "shortId", "recovery"]) {
      expect(serialized).not.toContain(`\"${forbidden}\"`);
    }
    const allEvidence = JSON.stringify({ sources: report.sources, gaps: report.gaps });
    expect(allEvidence).not.toMatch(/\/home\/[^/\"]+/);
    expect(allEvidence).not.toMatch(/\/Users\/[^/\"]+/);
    expect(allEvidence).not.toMatch(/\b[^\s\"]+@[^\s\"]+\.[^\s\"]+\b/);
    expect(allEvidence).not.toContain("sampleSessionIds");
  }, 60_000);
});
