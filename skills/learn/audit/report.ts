#!/usr/bin/env bun
// report.ts — render a /learn target-audit findings file to a self-contained
// HTML report. Each finding frames a problem the way it actually happened:
// expectation → what happened → why → proposed fix, anchored to the session
// that surfaced it so the user can recall the moment instantly.
//
// Usage: bun report.ts <findings.json> <meta.json> > report.html
//
// findings.json: Finding[]   meta.json: Meta   (schemas below)

import { readFileSync } from "node:fs";

type Severity = "high" | "medium" | "low";

interface Finding {
  severity: Severity;
  title: string; // one-line problem name
  expectation: string; // what was expected (the "before")
  what_happened: string; // what actually happened (the "after")
  why?: string; // root cause, if known
  quote?: string; // the grounding moment: a real user line / error text
  session_id: string;
  session_short?: string;
  session_topic?: string;
  session_ts?: string; // ISO timestamp of the session
  transcript_line?: number; // 1-based JSONL line of the moment
  recurrence_count?: number; // how many sessions show this problem
  recurrence_sessions?: string[]; // shortIds of the other sessions
  maybe_already_fixed?: boolean; // only seen in older sessions
  proposed_fix: string; // 1-2 lines: what the agent will change
  fix_target?: string; // where the fix lands (skill/rule/memory path)
}

interface Meta {
  target: string;
  target_kind?: string; // skill | plugin | command | tool | workflow
  scope_label?: string; // e.g. "this project, all time"
  sessions_scanned?: number;
  sessions_with_friction?: number;
  run_ts: string;
  rerun_command?: string;
}

const [findingsPath, metaPath] = process.argv.slice(2);
if (!findingsPath || !metaPath) {
  console.error("usage: report.ts <findings.json> <meta.json>");
  process.exit(1);
}

const findings: Finding[] = JSON.parse(readFileSync(findingsPath, "utf8"));
const meta: Meta = JSON.parse(readFileSync(metaPath, "utf8"));

const esc = (s: unknown): string =>
  String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");

const totals = {
  high: findings.filter((f) => f.severity === "high").length,
  medium: findings.filter((f) => f.severity === "medium").length,
  low: findings.filter((f) => f.severity === "low").length,
};

const payload = { findings, meta, totals };

const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>/learn audit — ${esc(meta.target)}</title>
<style>
  :root {
    --bg:#0f1115; --bg-elev:#181b22; --bg-elev-2:#1f232c; --border:#2a2f3a;
    --fg:#e6e6e6; --fg-muted:#9aa0aa; --fg-dim:#6a6f78; --accent:#b3ff0c;
    --high:#ff5c5c; --medium:#ffb454; --low:#5b9fff; --code-bg:#0b0d11;
    --mono: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  }
  * { box-sizing:border-box; }
  body { margin:0; background:var(--bg); color:var(--fg); font:14px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; }
  a { color:var(--accent); text-decoration:none; } a:hover { text-decoration:underline; }
  code { font-family:var(--mono); font-size:12.5px; }
  header { position:sticky; top:0; z-index:10; background:var(--bg-elev); border-bottom:1px solid var(--border); padding:14px 24px; }
  .scope { display:flex; gap:16px; align-items:center; flex-wrap:wrap; font-size:13px; color:var(--fg-muted); }
  .scope .label { color:#000; background:var(--accent); font-weight:700; padding:2px 9px; border-radius:6px; font-size:13px; }
  .scope .target { color:var(--fg); font-weight:600; font-size:15px; font-family:var(--mono); }
  .scope .mono { font-family:var(--mono); }
  .totals { display:flex; gap:10px; margin-top:11px; flex-wrap:wrap; }
  .badge { display:inline-flex; align-items:center; gap:6px; padding:4px 10px; border-radius:999px; font-size:12px; font-weight:600; background:var(--bg-elev-2); }
  .badge .num { font-variant-numeric:tabular-nums; }
  .badge.high { color:var(--high); border:1px solid color-mix(in srgb,var(--high) 30%,transparent); }
  .badge.medium { color:var(--medium); border:1px solid color-mix(in srgb,var(--medium) 30%,transparent); }
  .badge.low { color:var(--low); border:1px solid color-mix(in srgb,var(--low) 30%,transparent); }
  .filters { display:flex; flex-wrap:wrap; gap:8px; align-items:center; margin-top:12px; }
  .filters .group-label { color:var(--fg-dim); font-size:12px; margin-right:4px; }
  .chip { padding:4px 10px; border-radius:6px; background:var(--bg-elev-2); border:1px solid var(--border); color:var(--fg-muted); font-size:12px; cursor:pointer; user-select:none; }
  .chip:hover { color:var(--fg); }
  .chip.active { background:var(--accent); color:#000; border-color:var(--accent); font-weight:600; }
  .toolbar { display:flex; gap:12px; align-items:center; padding:10px 24px; background:var(--bg-elev); border-bottom:1px solid var(--border); font-size:12px; color:var(--fg-muted); }
  .toolbar button { background:var(--bg-elev-2); color:var(--fg); border:1px solid var(--border); padding:5px 12px; border-radius:6px; font-size:12px; cursor:pointer; }
  .toolbar button:hover:not(:disabled) { border-color:var(--accent); color:var(--accent); }
  .toolbar button:disabled { opacity:.4; cursor:not-allowed; }
  main { padding:16px 24px 60px; max-width:1080px; margin:0 auto; }
  .finding { background:var(--bg-elev); border:1px solid var(--border); border-left:3px solid var(--border); border-radius:8px; margin-bottom:10px; overflow:hidden; }
  .finding.high { border-left-color:var(--high); } .finding.medium { border-left-color:var(--medium); } .finding.low { border-left-color:var(--low); }
  .finding-head { display:flex; align-items:center; gap:10px; padding:10px 14px; cursor:pointer; user-select:none; }
  .finding-head:hover { background:var(--bg-elev-2); }
  .finding-checkbox { margin:0; cursor:pointer; width:15px; height:15px; }
  .finding-sev { font-size:10.5px; font-weight:700; padding:2px 8px; border-radius:4px; text-transform:uppercase; letter-spacing:.5px; }
  .finding.high .finding-sev { background:var(--high); color:#000; } .finding.medium .finding-sev { background:var(--medium); color:#000; } .finding.low .finding-sev { background:var(--low); color:#000; }
  .finding-title { flex:1; font-weight:600; color:var(--fg); }
  .finding-sess { font-family:var(--mono); font-size:11.5px; color:var(--fg-muted); white-space:nowrap; }
  .finding-flag { font-size:10px; font-weight:700; color:var(--low); border:1px solid color-mix(in srgb,var(--low) 35%,transparent); border-radius:4px; padding:1px 6px; text-transform:uppercase; letter-spacing:.4px; }
  .finding-toggle { color:var(--fg-dim); font-family:var(--mono); }
  .finding-body { padding:0 14px 14px; display:none; border-top:1px solid var(--border); }
  .finding.open .finding-body { display:block; padding-top:12px; }
  .ba { display:grid; grid-template-columns:max-content 1fr; gap:6px 14px; margin:8px 0; }
  .ba .k { color:var(--fg-dim); font-size:11px; text-transform:uppercase; letter-spacing:.5px; padding-top:2px; }
  .ba .v { color:var(--fg); }
  .ba .v.before { color:var(--fg-muted); }
  blockquote { margin:10px 0; padding:8px 12px; background:var(--code-bg); border-left:2px solid var(--fg-dim); border-radius:4px; color:#cfd3da; font-style:italic; white-space:pre-wrap; }
  .sessline { font-family:var(--mono); font-size:12px; color:var(--fg-muted); margin:8px 0 2px; }
  .recur { font-size:12px; color:var(--medium); margin-top:6px; }
  .finding-fix { margin-top:12px; padding:8px 10px; background:color-mix(in srgb,var(--accent) 8%,transparent); border-left:2px solid var(--accent); border-radius:4px; font-size:13px; }
  .finding-fix .label { color:var(--accent); font-weight:600; margin-right:6px; }
  .finding-fix .tgt { display:block; margin-top:4px; font-family:var(--mono); font-size:11.5px; color:var(--fg-dim); }
  .finding-actions { display:flex; gap:6px; margin-top:12px; flex-wrap:wrap; }
  .finding-actions button { background:var(--bg-elev-2); color:var(--fg-muted); border:1px solid var(--border); padding:4px 10px; border-radius:5px; font-size:11.5px; cursor:pointer; }
  .finding-actions button:hover, .finding-actions button.copied { color:var(--accent); border-color:var(--accent); }
  footer { margin-top:40px; padding:20px 24px; border-top:1px solid var(--border); background:var(--bg-elev); color:var(--fg-muted); font-size:12px; }
  .empty { padding:60px 0; text-align:center; color:var(--fg-muted); } .empty .big { font-size:48px; color:var(--accent); margin-bottom:8px; }
</style>
</head>
<body>
<header>
  <div class="scope">
    <span class="label">/learn audit</span>
    <span class="target">${esc(meta.target)}</span>
    ${meta.target_kind ? `<span>${esc(meta.target_kind)}</span>` : ""}
    <span>scope: <span class="mono">${esc(meta.scope_label || "—")}</span></span>
    <span><span class="mono">${meta.sessions_scanned ?? "?"}</span> sessions scanned · <span class="mono">${meta.sessions_with_friction ?? "?"}</span> with friction</span>
    <span>run: <span class="mono">${esc(meta.run_ts)}</span></span>
  </div>
  <div class="totals">
    <span class="badge high"><span class="num">${totals.high}</span> HIGH</span>
    <span class="badge medium"><span class="num">${totals.medium}</span> MEDIUM</span>
    <span class="badge low"><span class="num">${totals.low}</span> LOW</span>
  </div>
  <div class="filters">
    <span class="group-label">severity:</span>
    <span class="chip active" data-value="high">HIGH</span>
    <span class="chip active" data-value="medium">MEDIUM</span>
    <span class="chip active" data-value="low">LOW</span>
  </div>
</header>
<div class="toolbar">
  <span><span id="selcount">0</span> approved</span>
  <button id="batchbtn" disabled>Copy approved fixes → /learn apply</button>
  <button id="expandall">Expand all</button>
  <button id="collapseall">Collapse all</button>
  <span style="flex:1"></span>
  <span>rerun:&nbsp;<code>${esc(meta.rerun_command || "/learn " + meta.target)}</code></span>
</div>
<main id="report"></main>
<footer>
  Each problem is anchored to the session that surfaced it. Tick the fixes you approve, then
  <strong>Copy approved fixes → /learn apply</strong> and paste it back to the agent — it applies only what you approved,
  through the normal learn routing (skill / rule / memory) with a worktree + PR.
</footer>
<script id="payload" type="application/json">${JSON.stringify(payload).replace(/</g, "\\u003c")}</script>
<script>
(function () {
  const { findings, meta } = JSON.parse(document.getElementById("payload").textContent);
  const active = new Set(["high","medium","low"]);
  const approved = new Set();

  const esc = (s) => String(s ?? "")
    .replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;").replace(/'/g,"&#39;");
  const fp = (f, i) => i + "|" + (f.session_id||"") + "|" + (f.title||"");
  const sevRank = { high:0, medium:1, low:2 };

  const rel = (iso) => {
    if (!iso) return "";
    const t = Date.parse(iso); if (isNaN(t)) return esc(iso);
    const d = (Date.now() - t) / 86400000;
    if (d < 1) return "today";
    if (d < 2) return "yesterday";
    if (d < 30) return Math.round(d) + "d ago";
    if (d < 365) return Math.round(d/30) + "mo ago";
    return Math.round(d/365) + "y ago";
  };

  const copy = async (text, btn) => {
    try { await navigator.clipboard.writeText(text); const o = btn.textContent; btn.classList.add("copied"); btn.textContent = "\\u2713 copied"; setTimeout(()=>{ btn.classList.remove("copied"); btn.textContent=o; },1200); }
    catch(e){ btn.textContent = "\\u2717 failed"; }
  };
  const openCmd = (f) => "sessions " + (f.session_short || f.session_id) + " --markdown";
  const fixText = (f) => "Fix for \\"" + f.title + "\\" (" + (f.fix_target||"target") + "): " + f.proposed_fix;

  const card = (f, i) => {
    const id = esc(fp(f, i));
    const sess = (f.session_short || (f.session_id||"").slice(0,8));
    const recur = (f.recurrence_count && f.recurrence_count > 1)
      ? '<div class="recur">Recurred in ' + f.recurrence_count + ' sessions' + (f.recurrence_sessions && f.recurrence_sessions.length ? ' (' + f.recurrence_sessions.map(esc).join(", ") + ')' : '') + '</div>' : "";
    return \`
      <div class="finding \${f.severity}" data-fp="\${id}" data-sev="\${f.severity}">
        <div class="finding-head">
          <input type="checkbox" class="finding-checkbox" data-fp="\${id}" title="approve this fix">
          <span class="finding-sev">\${esc(f.severity)}</span>
          <span class="finding-title">\${esc(f.title)}</span>
          \${f.maybe_already_fixed ? '<span class="finding-flag">maybe fixed</span>' : ""}
          <span class="finding-sess">\${esc(sess)} · \${esc(rel(f.session_ts))}</span>
          <span class="finding-toggle">\${"\\u25b8"}</span>
        </div>
        <div class="finding-body">
          <div class="ba">
            <span class="k">Expected</span><span class="v before">\${esc(f.expectation)}</span>
            <span class="k">Happened</span><span class="v">\${esc(f.what_happened)}</span>
            \${f.why ? '<span class="k">Why</span><span class="v">' + esc(f.why) + '</span>' : ""}
          </div>
          \${f.quote ? '<blockquote>' + esc(f.quote) + '</blockquote>' : ""}
          <div class="sessline">session \${esc(f.session_id)}\${f.session_topic ? '  \\u00b7  "' + esc(f.session_topic) + '"' : ""}\${f.transcript_line ? '  \\u00b7  line ' + f.transcript_line : ""}</div>
          \${recur}
          <div class="finding-fix"><span class="label">Proposed fix:</span>\${esc(f.proposed_fix)}\${f.fix_target ? '<span class="tgt">\\u2192 ' + esc(f.fix_target) + '</span>' : ""}</div>
          <div class="finding-actions">
            <button data-action="open">Copy open-session cmd</button>
            <button data-action="fix">Copy fix plan</button>
          </div>
        </div>
      </div>\`;
  };

  const render = () => {
    const vis = findings
      .map((f, i) => ({ f, i }))
      .filter(({f}) => active.has(f.severity))
      .sort((a, b) => (sevRank[a.f.severity] - sevRank[b.f.severity]) || (Date.parse(b.f.session_ts||0) - Date.parse(a.f.session_ts||0)));
    const el = document.getElementById("report");
    if (!vis.length) {
      el.innerHTML = '<div class="empty"><div class="big">' + (findings.length ? "\\u00b7" : "\\u2713") + '</div><div>' + (findings.length ? "No findings match current filters." : "No friction found for " + esc(meta.target) + ".") + '</div></div>';
      return;
    }
    el.innerHTML = vis.map(({f, i}) => card(f, i)).join("");
  };

  document.querySelectorAll(".chip").forEach((c) => c.addEventListener("click", () => {
    const v = c.dataset.value;
    if (active.has(v)) { active.delete(v); c.classList.remove("active"); } else { active.add(v); c.classList.add("active"); }
    render();
  }));

  document.getElementById("report").addEventListener("click", (e) => {
    const c = e.target.closest(".finding"); if (!c) return;
    if (e.target.matches(".finding-checkbox")) {
      const k = e.target.dataset.fp;
      if (e.target.checked) approved.add(k); else approved.delete(k);
      document.getElementById("selcount").textContent = String(approved.size);
      document.getElementById("batchbtn").disabled = approved.size === 0;
      return;
    }
    if (e.target.matches("button[data-action]")) {
      const k = c.dataset.fp;
      const idx = findings.findIndex((f, i) => fp(f, i) === k);
      const f = findings[idx]; if (!f) return;
      copy(e.target.dataset.action === "open" ? openCmd(f) : fixText(f), e.target);
      return;
    }
    if (e.target.closest(".finding-head")) {
      c.classList.toggle("open");
      const t = c.querySelector(".finding-toggle"); if (t) t.textContent = c.classList.contains("open") ? "\\u25be" : "\\u25b8";
    }
  });

  document.getElementById("batchbtn").addEventListener("click", (e) => {
    const picks = findings.filter((f, i) => approved.has(fp(f, i)));
    const brief = "/learn apply " + meta.target + " — apply these " + picks.length + " approved fixes:\\n"
      + picks.map((f, n) => (n+1) + ". [" + f.severity + "] " + f.title
          + "\\n   fix: " + f.proposed_fix + (f.fix_target ? " (-> " + f.fix_target + ")" : "")
          + "\\n   evidence: session " + (f.session_short || f.session_id) + (f.transcript_line ? " line " + f.transcript_line : "")).join("\\n");
    copy(brief, e.target);
  });

  document.getElementById("expandall").addEventListener("click", () => document.querySelectorAll(".finding").forEach((c)=>{ c.classList.add("open"); const t=c.querySelector(".finding-toggle"); if(t)t.textContent="\\u25be"; }));
  document.getElementById("collapseall").addEventListener("click", () => document.querySelectorAll(".finding").forEach((c)=>{ c.classList.remove("open"); const t=c.querySelector(".finding-toggle"); if(t)t.textContent="\\u25b8"; }));
  render();
})();
</script>
</body>
</html>
`;

process.stdout.write(html);
