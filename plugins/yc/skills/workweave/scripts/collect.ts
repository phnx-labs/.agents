#!/usr/bin/env bun

import { basename, resolve } from "node:path";

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
export type SessionRow = Record<string, Json>;

class EngineFailure extends Error {
  constructor(readonly code: "command_failed" | "invalid_json" | "invalid_shape" | "project_group_missing") {
    super(code);
  }
}

function option(name: string): string | undefined {
  const index = Bun.argv.indexOf(name);
  return index === -1 ? undefined : Bun.argv[index + 1];
}

async function run(command: string[]): Promise<Json> {
  const process = Bun.spawn(command, { stdout: "pipe", stderr: "pipe" });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(process.stdout).text(),
    new Response(process.stderr).text(),
    process.exited,
  ]);
  if (exitCode !== 0) {
    throw new EngineFailure("command_failed");
  }
  try {
    return JSON.parse(stdout) as Json;
  } catch {
    throw new EngineFailure("invalid_json");
  }
}

async function text(command: string[]): Promise<string> {
  const process = Bun.spawn(command, { stdout: "pipe", stderr: "pipe" });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(process.stdout).text(),
    new Response(process.stderr).text(),
    process.exited,
  ]);
  if (exitCode !== 0) throw new Error(`${command.join(" ")} exited ${exitCode}: ${stderr.trim()}`);
  return stdout.trim();
}

function daysFor(window: string, sessions: Json): number {
  if (window === "all") {
    const rows = Array.isArray(sessions) ? sessions : [];
    const timestamps = rows
      .map((row) => (row && typeof row === "object" && !Array.isArray(row) ? row.timestamp : null))
      .filter((value): value is string => typeof value === "string")
      .map((value) => Date.parse(value))
      .filter(Number.isFinite);
    const earliest = timestamps.length ? Math.min(...timestamps) : Date.now();
    return Math.max(1, Math.ceil((Date.now() - earliest) / 86_400_000));
  }
  const days = windowDays(window);
  if (days === null) throw new Error(`Unsupported --since ${window}; use Nd, Nw, Nmo, or all`);
  return days;
}

function safeSession(row: SessionRow): SessionRow {
  return {
    agent: typeof row.agent === "string" ? row.agent : "unknown",
    timestamp: typeof row.timestamp === "string" ? row.timestamp : "",
    model: typeof row.model === "string" ? row.model : "unknown",
    messageCount: typeof row.messageCount === "number" ? row.messageCount : 0,
    outputTokens: typeof row.outputTokens === "number" ? row.outputTokens : 0,
    costUsd: typeof row.costUsd === "number" ? row.costUsd : 0,
    costUsdNoCache: typeof row.costUsdNoCache === "number" ? row.costUsdNoCache : 0,
    durationMs: typeof row.durationMs === "number" ? row.durationMs : 0,
  };
}

const privateKeys = new Set([
  "account", "accountKey", "accountOrg", "cwd", "filePath", "machine", "recovery",
  "sampleSessionIds", "session", "sessionId", "shortId", "topic", "topSessions",
]);

export function safeString(value: string): string {
  if (/\b[^\s@]+@[^\s@]+\.[^\s@]+\b/.test(value)) return "[redacted email]";
  return value
    .replace(/\b(token|secret|api[_-]?key|password)\s*[:=]\s*\S+/gi, "$1=[redacted secret]")
    .replace(/\bgh[pousr]_[A-Za-z0-9_]{20,}\b/g, "[redacted secret]")
    .replace(/\bsk-[A-Za-z0-9_-]{20,}\b/g, "[redacted secret]")
    .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g, "[redacted secret]")
    .replace(/[A-Za-z]:[\\/]Users[\\/][^\\/\s]+/gi, "~")
    .replace(/\/var\/home\/[^/\s]+/g, "~")
    .replace(/\/home\/[^/\s]+/g, "~")
    .replace(/\/Users\/[^/\s]+/g, "~")
    .replace(/\/root(?=\/|\s|$)/g, "~");
}

function safeEvidence(value: Json): Json {
  if (typeof value === "string") return safeString(value);
  if (Array.isArray(value)) return value.map(safeEvidence);
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(Object.entries(value)
    .filter(([key]) => !privateKeys.has(key))
    .map(([key, entry]) => [key, safeEvidence(entry)]));
}

export function selectProjectBehavior(value: Json, project: string): Json {
  if (!value || typeof value !== "object" || Array.isArray(value) || !Array.isArray(value.groups)) {
    throw new EngineFailure("invalid_shape");
  }
  const group = value.groups.find((entry) => entry && typeof entry === "object" && !Array.isArray(entry) && entry.key === project);
  if (!group) throw new EngineFailure("project_group_missing");
  return group;
}

function gapCode(error: unknown): string {
  return error instanceof EngineFailure ? error.code : "collector_error";
}

async function allSessions(project: string): Promise<SessionRow[]> {
  const byId = new Map<string, SessionRow>();
  let until: string | undefined;
  for (;;) {
    const command = ["agents", "sessions", "--project", project, "--all", "--limit", "1000", "--json"];
    if (until) command.push("--until", until);
    const page = await run(command);
    if (!Array.isArray(page)) throw new Error("agents sessions returned a non-array census");
    for (const value of page) {
      if (!value || typeof value !== "object" || Array.isArray(value)) continue;
      const id = typeof value.id === "string" ? value.id : null;
      if (id) byId.set(id, value as SessionRow);
    }
    if (page.length < 1000) break;
    const oldest = page
      .map((value) => value && typeof value === "object" && !Array.isArray(value) ? value.timestamp : null)
      .filter((value): value is string => typeof value === "string")
      .sort()[0];
    if (!oldest) throw new Error("Cannot paginate session census without timestamps");
    const next = new Date(Date.parse(oldest) - 1).toISOString();
    if (next === until) throw new Error(`Session pagination made no progress at ${oldest}`);
    until = next;
  }
  return [...byId.values()].map(safeSession);
}

function sum(rows: SessionRow[], key: string): number {
  return rows.reduce((total, row) => total + (typeof row[key] === "number" ? row[key] : 0), 0);
}

function windowDays(window: string): number | null {
  if (window === "all") return null;
  const match = /^(\d+)(d|w|mo)$/.exec(window);
  if (!match) throw new Error(`Unsupported --since ${window}; use Nd, Nw, Nmo, or all`);
  const count = Number(match[1]);
  return count * (match[2] === "d" ? 1 : match[2] === "w" ? 7 : 30);
}

export function filterSessions(rows: SessionRow[], window: string, now = Date.now()): SessionRow[] {
  if (window === "all") return rows;
  const days = windowDays(window);
  if (days === null) return rows;
  const cutoff = now - days * 86_400_000;
  return rows.filter((row) => typeof row.timestamp === "string" && Date.parse(row.timestamp) >= cutoff);
}

export function filterPreviousSessions(rows: SessionRow[], window: string, now = Date.now()): SessionRow[] {
  const days = windowDays(window);
  if (days === null) return [];
  const currentCutoff = now - days * 86_400_000;
  const previousCutoff = currentCutoff - days * 86_400_000;
  return rows.filter((row) => {
    if (typeof row.timestamp !== "string") return false;
    const timestamp = Date.parse(row.timestamp);
    return timestamp >= previousCutoff && timestamp < currentCutoff;
  });
}

function sessionTotals(rows: SessionRow[]) {
  return {
    sessions: rows.length,
    outputTokens: sum(rows, "outputTokens"),
    costUsd: sum(rows, "costUsd"),
    costUsdNoCache: sum(rows, "costUsdNoCache"),
    durationMs: sum(rows, "durationMs"),
    messages: sum(rows, "messageCount"),
  };
}

export function sessionComparison(current: SessionRow[], previous: SessionRow[]): Json {
  const currentTotals = sessionTotals(current);
  const previousTotals = sessionTotals(previous);
  const deltaPercent = Object.fromEntries(Object.keys(currentTotals).map((key) => {
    const currentValue = currentTotals[key as keyof typeof currentTotals];
    const previousValue = previousTotals[key as keyof typeof previousTotals];
    return [key, previousValue === 0 ? null : ((currentValue - previousValue) / previousValue) * 100];
  }));
  return { current: currentTotals, previous: previousTotals, deltaPercent };
}

export function sessionMetrics(rows: SessionRow[]): Json {
  const group = (key: "agent" | "model") => Object.entries(Object.groupBy(rows, (row) => String(row[key])))
    .map(([name, values]) => ({ name, sessions: values?.length ?? 0, outputTokens: sum(values ?? [], "outputTokens"), costUsd: sum(values ?? [], "costUsd") }));
  return {
    totals: sessionTotals(rows),
    byAgent: group("agent"),
    byModel: group("model"),
    daily: Object.entries(Object.groupBy(rows, (row) => String(row.timestamp).slice(0, 10)))
      .map(([day, values]) => ({ day, sessions: values?.length ?? 0, outputTokens: sum(values ?? [], "outputTokens"), costUsd: sum(values ?? [], "costUsd") }))
      .sort((a, b) => a.day.localeCompare(b.day)),
  };
}

async function main(): Promise<void> {
  const outputPath = option("--out");
  if (!outputPath) throw new Error("Missing --out <report-data.json>");

  const window = option("--since") ?? "30d";
  const origin = await text(["git", "remote", "get-url", "origin"]);
  const project = option("--project") ?? basename(origin.replace(/\.git$/, ""));

// This first query is intentionally separate: it refreshes the local index and supplies
// the all-time census used to turn `--since all` into concrete days for older engines.
  const sessions = await allSessions(project);
  const days = daysFor(window, sessions);
  const since = window === "all" ? `${days}d` : window;
  const now = Date.now();
  const windowSessions = filterSessions(sessions, window, now);
  const previousWindowSessions = filterPreviousSessions(sessions, window, now);

  const commands: Record<string, string[]> = {
  behavior: ["agents", "insights", "--since", since, "--by", "project", "--json"],
  harnessMix: ["agents", "insights", "harness-mix", "--days", String(days), "--json"],
  modelMix: ["agents", "insights", "model-mix", "--days", String(days), "--json"],
  tokenRatio: ["agents", "insights", "token-ratio", "--days", String(days), "--json"],
  sessionVolume: ["agents", "insights", "session-volume", "--days", String(days), "--json"],
  shippedOutput: ["agents", "insights", "output", "--since", since, "--by", "project", "--json"],
  resources: ["agents", "sessions", "stats", "--project", project, "--since", since, "--json"],
  unusedResources: ["agents", "sessions", "stats", "--project", project, "--since", since, "--zero", "--json"],
  hooks: ["agents", "perf", "hooks", "--days", String(days), "--project", project, "--json"],
  commands: ["agents", "perf", "commands", "--days", String(days), "--project", project, "--json"],
  friction: ["agents", "perf", "friction", "--days", String(days), "--json"],
  };

  const entries = await Promise.all(Object.entries(commands).map(async ([name, command]) => {
  try {
    const value = await run(command);
    return [name, name === "behavior" ? selectProjectBehavior(value, project) : value, null] as const;
  } catch (error) {
    return [name, null, gapCode(error)] as const;
  }
  }));

  const sources: Record<string, Json> = {
    sessions,
    sessionMetrics: sessionMetrics(windowSessions),
    sessionComparison: sessionComparison(windowSessions, previousWindowSessions),
  };
  const gaps: Record<string, string> = {};
  for (const [name, value, error] of entries) {
    if (error) gaps[name] = error;
    else sources[name] = safeEvidence(value);
  }

  const payload = {
    generatedAt: new Date().toISOString(),
    scope: { project, window, days, sessionCensus: "all-paginated", sessionCensusCount: sessions.length, windowSessionCount: windowSessions.length, friction: "fleet-wide", mix: "fleet-wide" },
    commands,
    sources,
    gaps,
  };
  await Bun.write(resolve(outputPath), `${JSON.stringify(payload, null, 2)}\n`);
  console.log(resolve(outputPath));
}

if (import.meta.main) await main();
