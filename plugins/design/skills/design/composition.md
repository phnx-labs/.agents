# Composing a page

[vocabulary.md](vocabulary.md) names the parts. This file is about putting them together:
how a handful of moves becomes one page that reads as made on purpose. Most weak pages are
not short of effects; they are short of composition. Read this when you design a page,
landing page or product surface from scratch, or when a critique says "it doesn't hang
together". The product's own `DESIGN.md` and brand guidance always win over this file.

Each rule below came from recording and taking apart 35 award-winning and developer-tool
sites, then building and reviewing two product sites with what was learned. The sites
named in parentheses are where the rule was observed.

## 1 · Write the thesis before choosing any move

Write the one sentence the page must make true, then let every section earn its place by
advancing it. "The chat ends. The artifact stays." decides that the hero shows a
conversation condensing into a page; "Every agent. Every machine. Landed." decides that
the signature scene ends on a merged pull request. If you cannot write the sentence, you
are choosing effects for their own sake.

## 2 · Pick the register, then borrow only from it

Award lists mix three different jobs. Borrow from the one you are doing.

| Register | Its job | Typical moves | Do not import |
| --- | --- | --- | --- |
| Experience (Igloo, Lusion, Messenger) | Be remembered; the site is the work | 3D scenes, preloaders, sound, physics, scroll-driven worlds | Into a tool site: loaders, entry gates, canvas-only content |
| Product (Linear, Stripe, Framer, Vercel) | Show the product doing its job and earn trust | A faithful product window, a scripted replay, proof panels, bento of facts | Effects that hide the product |
| Developer tool (Ghostty, Zed, Warp, artifacts-cli.sh) | Teach the mechanism in its own language | Terminal print, real command output, keyboard hints, figure captions | Marketing chrome, glow, stock 3D |

## 3 · One signature moment, everything else quiet

Every memorable site had exactly one thing you would describe to a friend: the igloo that
comes apart and back together (Igloo), the ASCII ghost blinking into a prompt (Ghostty),
Markdown building a page block by block (artifacts-cli.sh). Spend the motion budget there.
Make the signature the product doing its real job, not decoration around it. If two
sections both feel like the signature, demote one.

## 4 · Show the real mechanism, with real output

Prefer, in order: the product itself running, a scripted replay of a real session, a
faithful screenshot, an illustration. Anything that looks like output must be output. Run
the command, copy what it prints, and keep its formatting; a reviewer caught invented CLI
output on a page about that CLI, and that is the fastest way to lose a technical reader.
Label simulated data as an example.

## 5 · Pace the page like a story

A page is a sequence of scenes, read at scroll speed. A reliable arc:

1. **Hook:** thesis, one line of what it is, the primary action (install, start).
2. **Mechanism:** the signature scene; the reader sees how it works.
3. **Breadth:** a tour of the surface (scrollspy plus a printing terminal, feature tabs).
4. **The other half:** what the user does back (answers, notes, steering), so the product
   reads as a loop, not a one-way pipe.
5. **Trust:** facts as numbers, a comparison, what is free or local, FAQs.
6. **Close:** one action and the command to run.

Alternate dense and airy sections, and alternate scenes you watch with scenes you read.
Measured developer sites use about 96 to 128 px between sections at 1440 px wide.

## 6 · Give motion a budget and three clocks

Every animation belongs to exactly one clock:

- **Ambient** (seconds, answers nothing): at most one system per page, usually the
  backdrop. A sky, a field of motes.
- **Interface** (150 to 900 ms, answers the reader): reveals, scroll-driven scenes, hover.
  Ease out; nothing bounces or springs. No measured site bounced its hover.
- **Liveness** (a steady beat, about 2 s): only while something is actually running.

Nothing loops for decoration. A logo marquee that runs forever is a smell; tie it to
scroll so it rests when the reader does. Count before shipping: one ambient system, one
signature scene, quiet reveals, and liveness only where work is live.

## 7 · One focal point and one accent per view

In each screenful one element is clearly the thing to look at, and the accent colour is
spent once: the key word or the primary action, never borders or body text. When a view
feels busy, it almost always has two focal points or two accents.

## 8 · Continuity is what makes many effects one site

Repeat the same shapes so the reader learns them once: every terminal gets the same window
bar, every panel the same glass, every label the same eyebrow. Keep one type scale, radii
by role, and one backdrop that persists and changes with the page (a sky that descends to
a horizon at the footer) rather than a new background per section. Hand each section to
the next: end on what the following scene picks up, and draw the connection (a beam from
the page to the terminal) when two panes exchange something.

## 9 · The first frame is the page

The page is complete before any script runs and before the reader scrolls: reveals arm
only below the fold, staged hero loads hide nothing once motion is off, and
`prefers-reduced-motion` shows every scene finished. Five of the 35 recorded award sites
rendered only a loader or a blank canvas without a GPU, which is what crawlers, link
previews and slow machines see. Keep real content in HTML outside any canvas. Pinned
scenes become buttons on phones.

## 10 · Interactions must answer with something true

If the reader can act (answer a field, drag a revision slider), the response is
immediate, correct and stated in the product's real terms. A demo that accepts input and
returns canned nonsense is worse than a still image.

## 11 · Check contrast against the real backdrop

An ambient backdrop changes what text sits on. Measure text against the backdrop's worst
state, not the swatch: a caption that passes on the midday sky failed at sunrise and
sunset. Text on glass and text on bare backdrop may need different colours.

## 12 · Anti-patterns the research kept finding

Loader and entry gates on a site whose job is information. Scroll-jacking the wheel.
Effect soup: many signature-grade moves competing. Neon, glow and gradient borders as a
substitute for hierarchy. A fake terminal with invented output. Content only inside a
canvas. Decorative loops. Two accents in one view.

## Before you ship a composed page

- The thesis sentence is written and every section advances it.
- The signature moment is named, and it shows the real product working.
- One ambient system at most; every animation sits on one clock.
- Each view has one focal point and one accent.
- The first frame is complete without JavaScript; reduced motion shows the finished state.
- Phones get a deliberate version of every scene, not a squeezed desktop one.
- Every piece of shown output was produced by actually running it.
- Contrast is measured against the backdrop's worst state, in every theme.
