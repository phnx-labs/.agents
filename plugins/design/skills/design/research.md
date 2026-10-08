# Researching design references

Use this when a new direction needs evidence, when existing guidance is thin, or when the
user asks what good sites do. Research done this way surfaces moves and composition
lessons that asking "what do you think?" does not. It feeds [vocabulary.md](vocabulary.md)
and [composition.md](composition.md); add what it teaches there instead of leaving it in
one report.

## 1 · Choose the sites

Pick 20 to 35, in two groups:

- **Range:** recognised award winners (Awwwards Site of the Year and Site of the Day, FWA),
  for moves you would not think of.
- **Fit:** products in the same register as yours (see composition.md §2), for what
  actually suits the job.

Include the current version of your own page and any sibling sites as baselines. Check
each URL resolves before recording.

## 2 · Record a walkthrough of each

`scripts/record-sites.mjs` beside this file drives Playwright Chromium at 1440 x 900: a
pointer sweep over the hero, hovers on the first links, sixteen wheel ticks down, then one
jump back to the top. Per site it saves `walkthrough.mp4`, three stills, `fingerprint.json`
(libraries and techniques detected in the page; `null` means a cross-origin stylesheet
could not be read, not that the technique is absent) and `contact-sheet.jpg` (25 frames
spread over the recording).

```
printf '01-linear\thttps://linear.app/\n02-ghostty\thttps://ghostty.org/\n' > sites.tsv
npm i playwright && npx playwright install chromium
node <design-skill-dir>/scripts/record-sites.mjs sites.tsv research-out --concurrency 3
```

Run it on a worker machine rather than the user's laptop. Recording is software-rendered,
so heavy WebGL sites may capture only a loader or a blank canvas. Record that as the
capture quality instead of describing what the site probably does. Each site is capped at
110 s so a page that blocks the renderer cannot stall the run. A URL that fails to load is
reported as failed and the script exits non-zero; re-running retries only the failed sites.

## 3 · Analyse with the vocabulary

Read each contact sheet as a timeline, alongside the stills and the fingerprint, and tag
every observed move with its vocabulary ID. Give a move the vocabulary lacks a
`NEW-<name>` and a one-line definition. Per site, write:

- capture quality (good, partial, loader-only) and why
- the signature moment, with the frames where it shows
- each move as observed, visible in a still, or inferred from the fingerprint or HTML
- one or two things worth borrowing, in the register you are designing for

Split the sites across parallel analysts by batch when there are many; give every analyst
the same vocabulary so the tags merge.

## 4 · Synthesize into lasting guidance

Count how many sites show each move (how established it is), promote recurring
`NEW-` moves into vocabulary.md, and write down the composition lessons: what made a site
hang together, not just which effects it used. Measure what can be measured (section
padding, content width, hover timing) rather than estimating it.

## 5 · Deliver and keep

Give the user the folder: one subfolder per site with its video, contact sheet, stills,
fingerprint and notes, plus an index. Keep recordings out of git (size, and they are
third-party content); record where the folder lives. When the research changes the
guidance, render the vocabulary as an interactive field guide (a live specimen of each
move) with the `artifacts` skill.

Before any page shows command output, run the command and copy what it prints. Research
into how others present output is no substitute for the real output.
