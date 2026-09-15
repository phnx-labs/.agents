# Data visualization design

Read `design-core.md` beside this file. Create or refine a chart, infographic, or data
story. Use `design:prototype` for a full interactive product screen that includes charts.

1. Establish the question and inspect the data, units, provenance, and limitations.
   When refining, inspect the existing chart and its use before changing the encoding.
   Never invent values to make a graphic appear complete.
2. Choose a chart form suited to the comparison, trend, distribution, or relationship.
   Resolve the `artifacts` skill and its `references/diagram-conventions.md` for chart
   guidance. Use the existing visualization stack when refining a product; standard
   plotting tools suit scientific or exportable figures.
3. Label quantities and units, use honest scales (including zero baselines for bars),
   and expose uncertainty where relevant. Prefer direct labels when they reduce ambiguity.
   Reuse appropriate product colors; keep categories distinguishable without color alone.
4. For interactive charts, exercise filtering, selection, tooltips, empty data, and
   keyboard/focus behavior relevant to the task. Inspect the information users can access
   rather than judging only the default image.
5. Inspect the rendered output and any requested exports at their intended size. Verify
   labels and plotted values against the data. For refinement, compare before/after and
   explain the change in readability or behavior. Use the shared delivery guidance.
