# Shared design practice

Read this once for the selected design workflow. Use the product's conventions and the
user's scope; creating, refining, and reviewing are different tasks.

## 1 · Choose the right medium

Refine an existing app in its own stack and component library when implementation is
requested. A design-only request stays a proposal or prototype. For a standalone preview,
use editable HTML/SVG where suitable and the `artifacts` skill for authoring and delivery.
Offline previews should be self-contained; this does not require rebuilding a live app as
static HTML or removing its router and dependencies.

## 2 · Visual quality

Make hierarchy, alignment, density, typography, and spacing support the task. Reuse the
product's scales and patterns. Introduce new defaults only where no suitable pattern
exists, or where the requested redesign explicitly changes it. Explain consequential
changes rather than imposing a favorite palette, font, radius, or layout.

## 3 · Accessibility

Measure contrast from actual colors or computed styles; never guess ratios. Check text
against its real background (AA: 4.5:1 for ordinary text, 3:1 for large text). Do not encode
meaning by color alone. Exercise keyboard navigation and visible focus; inspect labels,
validation, disabled states, and touch use as relevant. Honor reduced-motion preferences.

## 4 · Understand the existing system

Find the applicable `DESIGN.md`, `BRAND.md`, rendered guidelines, tokens/theme files,
component library, assets, and relevant implementation. Read them together, not only the
first matching file. Follow the project's documented authority; distinguish intended
rules from implementation drift and resolve conflicts before introducing competing rules.

Open the actual rendered guidelines, Storybook, representative pages, and existing assets
visually using `browser` or `computer`. If only source exists, inspect it and render a
representative example when feasible. Identify repeated choices: type, spacing, density,
icon geometry, component variants, state feedback, navigation, and motion. Cite the
sources and captures that establish those patterns. Name unavailable surfaces and the
limits of screenshot-only evidence; do not invent their behavior.

## 5 · Reference work

Start with the product's own examples and the user's references. Browse relevant current
examples when exploring a new direction or when existing guidance is insufficient.
Inspect them before borrowing a specific choice; explain its relevance to the task.
Do not require competitor browsing for every small refinement.

## 6 · Heuristic checks

Generic style warnings are prompts to inspect, not universal design laws. An established
brand may deliberately use any palette or typeface. The static `check-tells.ts` checker
flags possible issues; judge each against the actual product and requested output.
Do not restyle a product simply to satisfy an arbitrary count of aesthetic warnings.

## 7 · Copy

Use precise language, realistic content, and the product's established voice. Labels
should explain actions and outcomes. Do not invent testimonials, usage counts, or claims.

## 8 · Raster assets

Use the available image capability when the requested deliverable needs generated or
edited raster artwork. Editable vector work is appropriate for many icons and logos.
A placeholder or generation brief is unfinished work, not a delivered image; label it
and report what remains if the required capability is unavailable.

## 9 · Verify and deliver

Inspect the result at the relevant sizes and themes. Repeat the affected interactions,
including a recovery or error path where applicable, and compare before and after when refining existing work.
Resolve the design plugin's `critique` skill through the current skill catalog for its
`scripts/check-contrast.ts` and `scripts/check-tells.ts`; resolve script paths from that
skill's directory. Use the contrast checker on actual pairs and the static checker on
available markup. Static checks cannot prove live interactions or full accessibility.

For authorized creation or refinement, fix findings and inspect the result again. Use `artifacts` for standalone previews and
`browser`/`computer` for the live surface. Show results through the configured viewer on
the user's machine. Follow repository worktree and artifact-location conventions; keep
captures local unless publication is authorized. State what changed, what was exercised,
and what remains unverified.

## 10 · Observe interactions before changing them

For an interactive surface, walk the relevant user journey before proposing changes:
entry, primary action, feedback, next step, back/cancel, and recovery. Inspect applicable
hover/focus, validation, loading, empty, error, and success states, responsive behavior,
and motion. Choose representative paths for the requested scope, not every page by default.

Record a short, bounded interaction clip when timing, transitions, scrolling, or a
multi-step sequence matters. Review its playback or extracted frames alongside the action
trace. Otherwise, use state captures and a short account of the actions and outcomes.
Use the `browser` or `computer` skill for supported capture mechanics. Review supplied
recordings too. A captured file alone is not evidence that anyone inspected it.

Separate observed behavior from proposed changes. Reuse and refine existing patterns
before adding new ones. Ask only for missing information or a consequential design choice;
do not stop routine authorized refinement behind a mandatory alternatives exercise.
