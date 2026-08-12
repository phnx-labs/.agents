---
kind: visual
template: visual.v1
title: 'Reference figure — before/after for one architectural move'
summary: 'Before/after for one architectural move, with every box and arrow sourced from modules.json.'
header: 'code:refactor'
footer: 'Generated from .agents/artifacts/<run>/modules.json — numbers in prose, figure, and JSON are one value.'
project: agents-cli
context: 'Reference implementation of the code:refactor figure contract. Numbers are from a real modules.json run on agents-cli; copy the SHAPE, never the numbers.'
repository: phnx-labs/agents-cli
branch: main
tracking: ''
status: draft
harness: ''
agent: ''
human: ''
host: ''
session: ''
date: '2026-08-12'
facts:
  - '44 modules, 196 module edges, 1 cycle spanning 38 of them'
  - 'lib: 193 files, 88,644 LOC, fan-in 1095, 84% of its files imported from outside'
  - 'lib/terminal: 17 files, 1,636 LOC, cohesion 0.84, 6 API files, 3 outbound deps'
links: []
assets: []
---

## Story

One architectural move, drawn under the skill's figure contract: **lift `lib/terminal` out
as a package**. The point of the contract is that the picture cannot drift from the code —
every box carries the module's real path, file count and LOC, and every arrow carries its
real import count, all read from `modules.json`.

The honest finding this figure has to show: `lib/terminal` is **not extractable today**. It
sits inside the 38-module cycle because it imports `lib` (4) and `lib/session` (4). The
move is therefore two steps, and the AFTER states exactly which edges must be inverted
first — an extraction proposed without that would be the sloppiness this contract exists to
prevent.

## Data

| Module | Files | LOC | Fan-in | Cohesion | API files | Outbound deps |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `lib` | 193 | 88,644 | 1,095 | 0.78 | 162 of 193 | — |
| `lib/session` | 60 | 28,671 | 239 | 0.52 | 49 of 60 | — |
| `lib/terminal` | 17 | 1,636 | 15 | 0.84 | 6 of 17 | 3 |

Inbound to `lib/terminal`: `commands` x10, `lib/watchdog` x3, `lib` x1, `lib/session` x1.
Outbound from `lib/terminal`: `lib` x4, `lib/session` x4, `lib/tmux` x1.

## Figure

<div class="artifact-behavior">
  <div class="artifact-behavior-panel" data-state="current" data-evidence="modules.json: edges[], modules[]">
    <svg viewBox="0 0 420 300" role="img" aria-label="Current: lib/terminal inside the dependency cycle, with 15 inbound and 9 outbound imports">
      <text fill="currentColor" x="10" y="18" font-size="11" font-weight="600">BEFORE — inside the 38-module cycle</text>
      <rect x="20" y="40" width="120" height="38" rx="4" fill="none" stroke="currentColor"/>
      <text fill="currentColor" x="30" y="58" font-size="10">commands</text>
      <text fill="currentColor" x="30" y="71" font-size="9" opacity="0.7">127 files</text>
      <rect x="270" y="40" width="130" height="38" rx="4" fill="none" stroke="currentColor"/>
      <text fill="currentColor" x="280" y="58" font-size="10">lib/watchdog</text>
      <text fill="currentColor" x="280" y="71" font-size="9" opacity="0.7">fan-in 3</text>
      <rect x="130" y="130" width="150" height="44" rx="4" fill="none" stroke="currentColor" stroke-width="2"/>
      <text fill="currentColor" x="140" y="149" font-size="10" font-weight="600">lib/terminal</text>
      <text fill="currentColor" x="140" y="163" font-size="9" opacity="0.7">17 files · 1,636 LOC</text>
      <rect x="20" y="230" width="120" height="38" rx="4" fill="none" stroke="currentColor"/>
      <text fill="currentColor" x="30" y="248" font-size="10">lib</text>
      <text fill="currentColor" x="30" y="261" font-size="9" opacity="0.7">193 files · 88,644 LOC</text>
      <rect x="270" y="230" width="130" height="38" rx="4" fill="none" stroke="currentColor"/>
      <text fill="currentColor" x="280" y="248" font-size="10">lib/session</text>
      <text fill="currentColor" x="280" y="261" font-size="9" opacity="0.7">60 files · 28,671 LOC</text>
      <line x1="80" y1="78" x2="175" y2="130" stroke="currentColor"/>
      <text fill="currentColor" x="105" y="108" font-size="9">x10</text>
      <line x1="335" y1="78" x2="240" y2="130" stroke="currentColor"/>
      <text fill="currentColor" x="290" y="108" font-size="9">x3</text>
      <line x1="175" y1="174" x2="80" y2="230" stroke="currentColor" stroke-dasharray="4 3"/>
      <text fill="currentColor" x="100" y="205" font-size="9">x4 out</text>
      <line x1="240" y1="174" x2="335" y2="230" stroke="currentColor" stroke-dasharray="4 3"/>
      <text fill="currentColor" x="280" y="205" font-size="9">x4 out</text>
      <text fill="currentColor" x="130" y="292" font-size="9" opacity="0.75">dashed = outbound edge that puts it in the cycle</text>
    </svg>
  </div>
  <div class="artifact-behavior-panel" data-state="proposed" data-evidence="derived: invert 8 outbound edges, then lift 17 files behind 6 API files">
    <svg viewBox="0 0 420 300" role="img" aria-label="Proposed: terminal as a package, consumed through 6 API files, zero outbound edges into lib">
      <text fill="currentColor" x="10" y="18" font-size="11" font-weight="600">AFTER — package, 0 edges into the cycle</text>
      <rect x="20" y="40" width="120" height="38" rx="4" fill="none" stroke="currentColor"/>
      <text fill="currentColor" x="30" y="58" font-size="10">commands</text>
      <text fill="currentColor" x="30" y="71" font-size="9" opacity="0.7">127 files</text>
      <rect x="270" y="40" width="130" height="38" rx="4" fill="none" stroke="currentColor"/>
      <text fill="currentColor" x="280" y="58" font-size="10">lib/watchdog</text>
      <text fill="currentColor" x="280" y="71" font-size="9" opacity="0.7">fan-in 3</text>
      <rect x="120" y="120" width="170" height="64" rx="4" fill="none" stroke="currentColor" stroke-width="2"/>
      <text fill="currentColor" x="130" y="139" font-size="10" font-weight="600">packages/terminal</text>
      <text fill="currentColor" x="130" y="153" font-size="9" opacity="0.7">17 files · 1,636 LOC</text>
      <text fill="currentColor" x="130" y="167" font-size="9" opacity="0.7">public API: 6 files</text>
      <text fill="currentColor" x="130" y="179" font-size="9" opacity="0.7">outbound deps: 0</text>
      <rect x="20" y="230" width="120" height="38" rx="4" fill="none" stroke="currentColor"/>
      <text fill="currentColor" x="30" y="248" font-size="10">lib</text>
      <text fill="currentColor" x="30" y="261" font-size="9" opacity="0.7">193 files · 88,644 LOC</text>
      <rect x="270" y="230" width="130" height="38" rx="4" fill="none" stroke="currentColor"/>
      <text fill="currentColor" x="280" y="248" font-size="10">lib/session</text>
      <text fill="currentColor" x="280" y="261" font-size="9" opacity="0.7">60 files · 28,671 LOC</text>
      <line x1="80" y1="78" x2="175" y2="120" stroke="currentColor"/>
      <text fill="currentColor" x="105" y="103" font-size="9">x10 via API</text>
      <line x1="335" y1="78" x2="245" y2="120" stroke="currentColor"/>
      <text fill="currentColor" x="290" y="103" font-size="9">x3 via API</text>
      <line x1="80" y1="230" x2="160" y2="184" stroke="currentColor"/>
      <text fill="currentColor" x="86" y="212" font-size="9">x4 INVERTED</text>
      <line x1="335" y1="230" x2="255" y2="184" stroke="currentColor"/>
      <text fill="currentColor" x="262" y="212" font-size="9">x4 INVERTED</text>
      <text fill="currentColor" x="120" y="292" font-size="9" opacity="0.75">8 outbound edges inverted first — else the package drags the SCC</text>
    </svg>
  </div>
</div>

<div class="artifact-callout-warn">
  <strong>Sequencing.</strong> This move is blocked until the 8 outbound edges
  (<code>lib</code> x4, <code>lib/session</code> x4) are inverted, because
  <code>lib/terminal</code> is currently one of the 38 modules in the single cycle.
  Extraction before that ships a package that drags the whole SCC with it.
</div>
