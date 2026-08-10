# design:critique — review an existing screen or asset

Run the design-core checklist on something that already exists (a screenshot, a URL, or an
HTML file) and return a concrete, prioritized verdict. This is the standalone form of the
verification every other mode runs on its own output.

## Load design-core first

Read `design-core.md`. Its 11-item checklist is the rubric; this mode runs it against the
input rather than against your own render.

## When to use (vs neighbors)

- Judge or improve something that exists → **critique** (this).
- Then rebuild it → hand off to **`interface`** (redesign path).

## The loop

1. **Capture the artifact.** A screenshot (read it), a URL (open + screenshot), or an HTML
   file (render + screenshot). Look at it; never critique from a description.
2. **Score the 11-item checklist** (design-core): focal point, hierarchy, alignment/rhythm,
   type, color, contrast, copy, density, consistency, anti-tells (§6), intent. Each is a
   pass or a specific fix.
3. **Prioritize.** Order fixes by impact: correctness and accessibility first (contrast,
   color-alone, intent), then hierarchy and rhythm, then polish.
4. **Be concrete.** "The h1 and body are the same weight, so there is no focal point; set
   the h1 to 600 / 32px" beats "improve hierarchy". Quote the element and give the number.

## Output & delivery

- A short **verdict**: what works, then a prioritized fix list (each item names what, why,
  and the concrete change). No marketing language. Keyless.
- Offer to run **`interface`** to rebuild the screen addressing the list.

## Mode checklist

- [ ] You looked at the rendered artifact (screenshot in hand), not a description.
- [ ] Every finding cites a concrete element and a concrete change.
- [ ] Fixes ordered by impact; accessibility and intent first.
- [ ] Verdict copy is precise and non-marketing.
