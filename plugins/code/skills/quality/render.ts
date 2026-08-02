#!/usr/bin/env bun
// Renders findings JSON to a self-contained HTML report.
// Usage: bun render.ts <findings.json> <run-dir>
// Outputs HTML to stdout.

import { readFileSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";

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

interface Meta {
  scope_mode: string;
  scope_label: string;
  rerun_command: string;
  run_ts: string;
  surfaces: string[];
  skipped_tools: string[];
  repo_root: string;
}

const [findingsPath, runDir] = process.argv.slice(2);
if (!findingsPath || !runDir) {
  console.error("usage: render.ts <findings.json> <run-dir>");
  process.exit(1);
}

const findings: Finding[] = JSON.parse(readFileSync(findingsPath, "utf8"));

const metaPath = join(runDir, "meta.json");
const meta: Meta = existsSync(metaPath)
  ? JSON.parse(readFileSync(metaPath, "utf8"))
  : {
      scope_mode: "unknown",
      scope_label: "unknown",
      rerun_command: "/quality",
      run_ts: new Date().toISOString(),
      surfaces: [],
      skipped_tools: [],
      repo_root: "",
    };

const CATEGORY_LABEL: Record<Category, string> = {
  architecture: "Architecture & Design",
  "code-health": "Code Health",
  context: "Context Quality",
  patterns: "Patterns",
};

const totals = {
  blocker: findings.filter((f) => f.severity === "blocker").length,
  should: findings.filter((f) => f.severity === "should").length,
  nice: findings.filter((f) => f.severity === "nice").length,
};

const escape = (s: string): string =>
  s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");

const payload = {
  findings,
  meta,
  category_label: CATEGORY_LABEL,
  totals,
  total_findings: findings.length,
};

const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>/quality report — ${escape(meta.scope_label)}</title>
<style>
  :root {
    --bg: #0f1115;
    --bg-elev: #181b22;
    --bg-elev-2: #1f232c;
    --border: #2a2f3a;
    --fg: #e6e6e6;
    --fg-muted: #9aa0aa;
    --fg-dim: #6a6f78;
    --accent: #b3ff0c;
    --blocker: #ff5c5c;
    --should: #ffb454;
    --nice: #5b9fff;
    --code-bg: #0b0d11;
    --mono: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--fg); font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
  a { color: var(--accent); text-decoration: none; }
  a:hover { text-decoration: underline; }
  code, pre { font-family: var(--mono); font-size: 12.5px; }
  header {
    position: sticky; top: 0; z-index: 10;
    background: var(--bg-elev); border-bottom: 1px solid var(--border);
    padding: 14px 24px;
  }
  .scope { display: flex; gap: 16px; align-items: center; font-size: 13px; color: var(--fg-muted); }
  .scope .label { color: var(--fg); font-weight: 600; font-size: 14px; }
  .scope .mono { font-family: var(--mono); }
  .totals { display: flex; gap: 10px; margin-top: 10px; }
  .badge {
    display: inline-flex; align-items: center; gap: 6px;
    padding: 4px 10px; border-radius: 999px;
    font-size: 12px; font-weight: 600;
    background: var(--bg-elev-2);
  }
  .badge .num { font-variant-numeric: tabular-nums; }
  .badge.blocker { color: var(--blocker); border: 1px solid color-mix(in srgb, var(--blocker) 30%, transparent); }
  .badge.should { color: var(--should); border: 1px solid color-mix(in srgb, var(--should) 30%, transparent); }
  .badge.nice { color: var(--nice); border: 1px solid color-mix(in srgb, var(--nice) 30%, transparent); }

  .filters { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-top: 12px; }
  .filters .group-label { color: var(--fg-dim); font-size: 12px; margin-right: 4px; }
  .chip {
    padding: 4px 10px; border-radius: 6px;
    background: var(--bg-elev-2); border: 1px solid var(--border);
    color: var(--fg-muted); font-size: 12px; cursor: pointer;
    user-select: none;
  }
  .chip:hover { color: var(--fg); }
  .chip.active { background: var(--accent); color: #000; border-color: var(--accent); font-weight: 600; }

  .toolbar {
    display: flex; gap: 12px; align-items: center;
    padding: 10px 24px; background: var(--bg-elev); border-bottom: 1px solid var(--border);
    font-size: 12px; color: var(--fg-muted);
  }
  .toolbar button {
    background: var(--bg-elev-2); color: var(--fg); border: 1px solid var(--border);
    padding: 5px 12px; border-radius: 6px; font-size: 12px; cursor: pointer;
  }
  .toolbar button:hover:not(:disabled) { border-color: var(--accent); color: var(--accent); }
  .toolbar button:disabled { opacity: 0.4; cursor: not-allowed; }

  main { padding: 16px 24px 60px; max-width: 1200px; margin: 0 auto; }
  .category-section { margin-bottom: 28px; }
  .category-header {
    display: flex; justify-content: space-between; align-items: baseline;
    padding: 8px 0 12px;
    border-bottom: 1px solid var(--border);
    margin-bottom: 12px;
  }
  .category-title { font-size: 16px; font-weight: 600; color: var(--fg); }
  .category-counts { font-size: 12px; color: var(--fg-muted); font-variant-numeric: tabular-nums; }
  .category-counts .blocker { color: var(--blocker); }
  .category-counts .should { color: var(--should); }
  .category-counts .nice { color: var(--nice); }

  .finding {
    background: var(--bg-elev); border: 1px solid var(--border); border-left: 3px solid var(--border);
    border-radius: 8px; margin-bottom: 10px; overflow: hidden;
  }
  .finding.blocker { border-left-color: var(--blocker); }
  .finding.should { border-left-color: var(--should); }
  .finding.nice { border-left-color: var(--nice); }
  .finding-head {
    display: flex; align-items: center; gap: 10px;
    padding: 10px 14px; cursor: pointer; user-select: none;
  }
  .finding-head:hover { background: var(--bg-elev-2); }
  .finding-checkbox { margin: 0; cursor: pointer; }
  .finding-sev {
    font-size: 10.5px; font-weight: 700; padding: 2px 8px; border-radius: 4px;
    text-transform: uppercase; letter-spacing: 0.5px;
  }
  .finding.blocker .finding-sev { background: var(--blocker); color: #000; }
  .finding.should .finding-sev { background: var(--should); color: #000; }
  .finding.nice .finding-sev { background: var(--nice); color: #000; }
  .finding-rule { flex: 1; font-weight: 500; color: var(--fg); }
  .finding-loc { font-family: var(--mono); font-size: 12px; color: var(--fg-muted); }
  .finding-loc a { color: var(--fg-muted); }
  .finding-loc a:hover { color: var(--accent); }
  .finding-toggle { color: var(--fg-dim); font-family: var(--mono); }

  .finding-body { padding: 0 14px 14px; display: none; border-top: 1px solid var(--border); }
  .finding.open .finding-body { display: block; padding-top: 12px; }
  .finding-section-label { color: var(--fg-dim); font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; margin: 10px 0 4px; }
  .finding-anchor-loc { font-family: var(--mono); font-size: 12px; color: var(--fg-muted); margin-bottom: 6px; }

  pre.snippet {
    background: var(--code-bg); border: 1px solid var(--border); border-radius: 6px;
    padding: 8px 10px; margin: 4px 0;
    overflow-x: auto; white-space: pre;
    color: #d4d4d4;
  }
  pre.snippet .ln {
    display: inline-block; width: 3em; color: var(--fg-dim); text-align: right; margin-right: 12px;
    user-select: none;
  }
  .finding-fix {
    margin-top: 12px; padding: 8px 10px;
    background: color-mix(in srgb, var(--accent) 8%, transparent);
    border-left: 2px solid var(--accent);
    border-radius: 4px;
    font-size: 13px;
  }
  .finding-fix .label { color: var(--accent); font-weight: 600; margin-right: 6px; }

  .finding-actions { display: flex; gap: 6px; margin-top: 12px; flex-wrap: wrap; }
  .finding-actions button {
    background: var(--bg-elev-2); color: var(--fg-muted); border: 1px solid var(--border);
    padding: 4px 10px; border-radius: 5px; font-size: 11.5px; cursor: pointer;
  }
  .finding-actions button:hover { color: var(--accent); border-color: var(--accent); }
  .finding-actions button.copied { color: var(--accent); border-color: var(--accent); }

  footer {
    margin-top: 40px; padding: 20px 24px; border-top: 1px solid var(--border);
    background: var(--bg-elev); color: var(--fg-muted); font-size: 12px;
  }
  footer h3 { color: var(--fg); font-size: 13px; margin: 0 0 6px; font-weight: 600; }
  footer ul { margin: 0; padding-left: 20px; }
  footer li { margin-bottom: 3px; }
  .empty { padding: 60px 0; text-align: center; color: var(--fg-muted); }
  .empty .big { font-size: 48px; color: var(--accent); margin-bottom: 8px; }
</style>
</head>
<body>
<header>
  <div class="scope">
    <span class="label">/quality</span>
    <span>scope: <span class="mono">${escape(meta.scope_label)}</span></span>
    <span>run: <span class="mono">${escape(meta.run_ts)}</span></span>
  </div>
  <div class="totals">
    <span class="badge blocker"><span class="num">${totals.blocker}</span> BLOCKER</span>
    <span class="badge should"><span class="num">${totals.should}</span> SHOULD</span>
    <span class="badge nice"><span class="num">${totals.nice}</span> NICE</span>
  </div>
  <div class="filters">
    <span class="group-label">severity:</span>
    <span class="chip active" data-filter="severity" data-value="blocker">BLOCKER</span>
    <span class="chip active" data-filter="severity" data-value="should">SHOULD</span>
    <span class="chip active" data-filter="severity" data-value="nice">NICE</span>
    <span class="group-label" style="margin-left:14px">category:</span>
    <span class="chip active" data-filter="category" data-value="architecture">arch</span>
    <span class="chip active" data-filter="category" data-value="code-health">code</span>
    <span class="chip active" data-filter="category" data-value="context">context</span>
    <span class="chip active" data-filter="category" data-value="patterns">patterns</span>
  </div>
</header>
<div class="toolbar">
  <span><span id="selcount">0</span> selected</span>
  <button id="batchbtn" disabled>Create task batch (clipboard)</button>
  <button id="expandall">Expand all</button>
  <button id="collapseall">Collapse all</button>
  <span style="flex:1"></span>
  <span>rerun:&nbsp;<code class="mono">${escape(meta.rerun_command)}</code></span>
</div>
<main id="report"></main>
<footer>
  <h3>Skipped checks (transparency)</h3>
  <ul>
    <li><strong>Halstead Volume</strong> — magic-number constants, ~nobody uses, no actionable signal.</li>
    <li><strong>Maintainability Index</strong> — overfit to C/Pascal, LOC-correlated, no root-cause value.</li>
    <li><strong>Naked LOC / function-line thresholds</strong> — arbitrary; punishes legitimate switch chains.</li>
  </ul>
  ${
    meta.skipped_tools.length > 0
      ? `<h3 style="margin-top:14px">Tools not on PATH this run</h3>
  <ul>${meta.skipped_tools.map((t) => `<li><code>${escape(t)}</code></li>`).join("")}</ul>`
      : ""
  }
</footer>
<script id="payload" type="application/json">${JSON.stringify(payload).replace(/</g, "\\u003c")}</script>
<script>
(function () {
  const PAYLOAD = JSON.parse(document.getElementById("payload").textContent);
  const { findings, category_label, total_findings } = PAYLOAD;
  const filters = { severity: new Set(["blocker","should","nice"]), category: new Set(["architecture","code-health","context","patterns"]) };
  const selected = new Set();

  const esc = (s) => String(s)
    .replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;")
    .replace(/"/g,"&quot;").replace(/'/g,"&#39;");

  const fingerprint = (f) => f.category + "|" + f.file + ":" + f.line_start + "|" + f.rule;

  // Open-by-default rule based on scale
  const openByDefault = (f) => {
    if (total_findings <= 20) return true;
    if (total_findings <= 100) return f.severity === "blocker";
    return false;
  };

  const renderSnippet = (snippet, startLine) => {
    if (!snippet) return "";
    const lines = String(snippet).split("\\n");
    return "<pre class='snippet'>" + lines.map((l, i) => {
      const n = (Number(startLine) || 1) + i;
      return "<span class='ln'>" + n + "</span>" + esc(l);
    }).join("\\n") + "</pre>";
  };

  const fileLink = (file, line) => {
    const abs = PAYLOAD.meta.repo_root ? (PAYLOAD.meta.repo_root + "/" + file) : file;
    return "<a href='vscode://file/" + esc(abs) + ":" + (line||1) + "'>" + esc(file) + ":" + (line||"") + "</a>";
  };

  const loopBrief = (f) => {
    let s = "/code:loop \\"Fix " + f.rule + " at " + f.file + ":" + f.line_start;
    if (f.anchor_file) s += ". Pattern to follow: " + f.anchor_file + ":" + (f.anchor_line || "");
    if (f.fix_one_line) s += ". Approach: " + f.fix_one_line;
    return s + "\\"";
  };

  const linearBrief = (f) => {
    const desc = "File: " + f.file + ":" + f.line_start
      + (f.anchor_file ? "\\nCanonical: " + f.anchor_file + ":" + (f.anchor_line || "") : "")
      + (f.fix_one_line ? "\\nFix: " + f.fix_one_line : "");
    return "linear issue create --title " + JSON.stringify(f.rule) + " --description " + JSON.stringify(desc);
  };

  const fileLineText = (f) => f.file + ":" + f.line_start;

  const copyToClipboard = async (text, btn) => {
    try {
      await navigator.clipboard.writeText(text);
      btn.classList.add("copied");
      const original = btn.textContent;
      btn.textContent = "✓ copied";
      setTimeout(() => { btn.classList.remove("copied"); btn.textContent = original; }, 1200);
    } catch (e) {
      console.error(e);
      btn.textContent = "✗ failed";
    }
  };

  const renderFinding = (f) => {
    const fp = fingerprint(f);
    const open = openByDefault(f);
    return \`
      <div class="finding \${f.severity} \${open ? "open" : ""}" data-fp="\${esc(fp)}" data-severity="\${f.severity}" data-category="\${f.category}">
        <div class="finding-head">
          <input type="checkbox" class="finding-checkbox" data-fp="\${esc(fp)}">
          <span class="finding-sev">\${f.severity}</span>
          <span class="finding-rule">\${esc(f.rule)}</span>
          <span class="finding-loc">\${fileLink(f.file, f.line_start)}</span>
          <span class="finding-toggle">\${open ? "▾" : "▸"}</span>
        </div>
        <div class="finding-body">
          \${renderSnippet(f.snippet, f.line_start)}
          \${f.anchor_file ? \`
            <div class="finding-section-label">canonical pattern</div>
            <div class="finding-anchor-loc">\${fileLink(f.anchor_file, f.anchor_line)}</div>
            \${renderSnippet(f.anchor_snippet, f.anchor_line)}
          \` : ""}
          \${f.fix_one_line ? \`<div class="finding-fix"><span class="label">Fix:</span>\${esc(f.fix_one_line)}</div>\` : ""}
          <div class="finding-actions">
            <button data-action="loop">Copy as /loop task</button>
            <button data-action="linear">Copy Linear cmd</button>
            <button data-action="fileline">Copy file:line</button>
            <span style="flex:1"></span>
            <span style="font-size:11px;color:var(--fg-dim)">tool: \${esc(f.tool || "")}</span>
          </div>
        </div>
      </div>
    \`;
  };

  const renderReport = () => {
    const visible = findings.filter((f) => filters.severity.has(f.severity) && filters.category.has(f.category));
    if (visible.length === 0) {
      document.getElementById("report").innerHTML = \`
        <div class="empty">
          <div class="big">\${total_findings === 0 ? "✓" : "·"}</div>
          <div>\${total_findings === 0 ? "No findings." : "No findings match current filters."}</div>
        </div>
      \`;
      return;
    }
    const groups = {};
    for (const f of visible) (groups[f.category] = groups[f.category] || []).push(f);
    const order = ["architecture","code-health","context","patterns"];
    let html = "";
    for (const cat of order) {
      if (!groups[cat]) continue;
      const list = groups[cat];
      const b = list.filter((f)=>f.severity==="blocker").length;
      const s = list.filter((f)=>f.severity==="should").length;
      const n = list.filter((f)=>f.severity==="nice").length;
      html += \`
        <section class="category-section">
          <div class="category-header">
            <span class="category-title">\${esc(category_label[cat] || cat)}</span>
            <span class="category-counts">
              <span class="blocker">\${b}B</span>&nbsp;·&nbsp;<span class="should">\${s}S</span>&nbsp;·&nbsp;<span class="nice">\${n}N</span>
            </span>
          </div>
          \${list.map(renderFinding).join("")}
        </section>
      \`;
    }
    document.getElementById("report").innerHTML = html;
  };

  document.querySelectorAll(".chip").forEach((chip) => {
    chip.addEventListener("click", () => {
      const f = chip.dataset.filter, v = chip.dataset.value;
      if (filters[f].has(v)) { filters[f].delete(v); chip.classList.remove("active"); }
      else { filters[f].add(v); chip.classList.add("active"); }
      renderReport();
    });
  });

  document.getElementById("report").addEventListener("click", (e) => {
    const card = e.target.closest(".finding");
    if (!card) return;
    if (e.target.matches(".finding-checkbox")) {
      const fp = e.target.dataset.fp;
      if (e.target.checked) selected.add(fp); else selected.delete(fp);
      document.getElementById("selcount").textContent = String(selected.size);
      document.getElementById("batchbtn").disabled = selected.size === 0;
      return;
    }
    if (e.target.matches("button[data-action]")) {
      const action = e.target.dataset.action;
      const fp = card.dataset.fp;
      const f = findings.find((x) => fingerprint(x) === fp);
      if (!f) return;
      const text = action === "loop" ? loopBrief(f)
                  : action === "linear" ? linearBrief(f)
                  : action === "fileline" ? fileLineText(f) : "";
      copyToClipboard(text, e.target);
      return;
    }
    if (e.target.closest(".finding-head")) {
      card.classList.toggle("open");
      const t = card.querySelector(".finding-toggle");
      if (t) t.textContent = card.classList.contains("open") ? "▾" : "▸";
    }
  });

  document.getElementById("batchbtn").addEventListener("click", (e) => {
    const picks = findings.filter((f) => selected.has(fingerprint(f)));
    const brief = "/code:loop \\"Address the following " + picks.length + " findings from /quality:\\n"
      + picks.map((f, i) => (i+1) + ". " + f.rule + " at " + f.file + ":" + f.line_start
                            + (f.anchor_file ? " (pattern: " + f.anchor_file + ":" + (f.anchor_line||"") + ")" : "")
                            + (f.fix_one_line ? " — " + f.fix_one_line : "")).join("\\n")
      + "\\"";
    copyToClipboard(brief, e.target);
  });

  document.getElementById("expandall").addEventListener("click", () => {
    document.querySelectorAll(".finding").forEach((c) => {
      c.classList.add("open");
      const t = c.querySelector(".finding-toggle"); if (t) t.textContent = "▾";
    });
  });
  document.getElementById("collapseall").addEventListener("click", () => {
    document.querySelectorAll(".finding").forEach((c) => {
      c.classList.remove("open");
      const t = c.querySelector(".finding-toggle"); if (t) t.textContent = "▸";
    });
  });

  renderReport();
})();
</script>
</body>
</html>
`;

process.stdout.write(html);
