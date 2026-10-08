# Design and interaction vocabulary

Names for what a page does and how it is built, so a request, a critique or a plan can say exactly which move it means. Use the name and the ID together ("pinned scrollytelling, S3"). Load this when proposing, specifying or critiquing a visual surface; pair it with [composition.md](composition.md), which says how these pieces combine into one page.

Source: the Design & Interaction Field Guide, built from scripted walkthroughs of 35 award-winning and developer-tool sites (30 captured fully). "Seen" counts how many of those sites showed the move; it measures how established a move is, not whether it fits your page. The live, interactive version of every entry is the rendered guide (see [research.md](research.md) for where it and the recordings live).

Every motion entry implies two obligations: the page is complete before JavaScript runs, and `prefers-reduced-motion` gets the finished state.

## Part one: interaction

Motion and response: what moves, when, and what answers the pointer.

### S · Scroll

Effects tied to the reader's scroll position or speed. The most powerful category and the easiest to overdo.

| ID | Name | Ask for it | Cost and care | Seen |
| --- | --- | --- | --- | --- |
| S1 | Reveal on enter | Fade each block up a little as it scrolls into view, once. | Cheap. Arm only blocks below the fold so the first frame is complete. | 9 |
| S2 | Parallax layers | Make the background layer move slower than the foreground as I scroll. | Cheap with transforms. Keep the speed difference small or it feels seasick. | 3 |
| S3 | Pinned scrollytelling | Pin this section and let scroll step through its states, rewinding when I scroll up. | Medium. Give phones a version with buttons instead of pinning. | 5 |
| S4 | Scroll-scrubbed sequence | Play this image sequence frame by frame as I scroll, like Apple product pages. | Heavy: dozens of frames to download. Preload smartly. | — |
| S5 | Horizontal scroll section | While this section is pinned, turn my vertical scroll into a sideways move through the cards. | Medium. Disorients some readers; never hijack the wheel itself. | 3 |
| S6 | Stacking cards | Make the cards stick and pile on top of each other as I scroll. | Cheap, pure CSS position: sticky. | 1 |
| S7 | Scroll-linked text fill | Light the words of this paragraph one by one as it passes the middle of the screen. | Cheap. Reduced motion shows the paragraph fully lit. | — |
| S8 | Zoom-through | Grow this image until it fills the screen as I scroll into it. | Medium. Use a pinned wrapper. | 3 |
| S9 | Smooth inertial scroll | Give scrolling a soft, eased glide (Lenis style). | Divisive: can feel laggy, breaks some anchors. Ask for it on purpose. | 10 |
| S10 | Scroll velocity effects | Make the strip slide and lean with how fast I scroll. | Cheap. It must come to rest when scrolling stops. | — |
| S11 | Theme shift on scroll | Change the page's background color as each section arrives. | Cheap. Check contrast in every state. | 2 |
| S12 | Scrollspy | Highlight the step or nav item for whatever is in the middle of the screen. | Cheap and useful. Good for long docs too. | 8 |
| S13 | Ambient backdrop on scroll | Let the sky gradient pan from top to horizon as I scroll down the page. | Cheap. Keep text contrast on every part of it. | 1 |

### T · Type

Motion and treatment of the words themselves.

| ID | Name | Ask for it | Cost and care | Seen |
| --- | --- | --- | --- | --- |
| T1 | Split-text stagger | Bring the headline in word by word. | Cheap. Keep words, not letters, for readable headlines. | 9 |
| T2 | Line mask reveal | Slide each line of the headline up from behind an invisible edge. | Cheap. Very editorial. | — |
| T3 | Scramble / decode | Make the text flicker through random characters, then resolve. | Cheap. Reads as hacker cliché if overused. | 3 |
| T4 | Terminal print | Type out these terminal lines one after another. | Cheap. Print once; don't loop. | 1 |
| T5 | Marquee / ticker | Run a continuous strip of logos or words across the screen. | Cheap. A decorative loop; pause on hover, stop for reduced motion. | 2 |
| T6 | Variable-font motion | Make the heading get bolder under the cursor. | Cheap with a variable font. | — |
| T7 | Metallic sheen on text | Run a light sweep across the headline once. | Cheap. Once, not on a loop. | 3 |
| T8 | Number counter | Count the number up when it enters the view. | Cheap. Marketing cliché; show the real number at rest. | 2 |
| T9 | Oversized display type | Set the closing wordmark as wide as the page. | Free. One per page. | 13 |

### C · Cursor and pointer

Things that answer the mouse. Desktop only; give phones a still version.

| ID | Name | Ask for it | Cost and care | Seen |
| --- | --- | --- | --- | --- |
| C1 | Cursor follower | Have a soft circle trail my cursor. | Cheap. Desktop only. Do not hide the real cursor. | 11 |
| C2 | Magnetic button | Pull this button slightly toward the cursor when it's near. | Cheap. Subtle is key. | 1 |
| C3 | Spotlight | Light the surface where the pointer is. | Cheap. | 1 |
| C4 | 3D tilt | Tilt the card toward the mouse. | Cheap. Easy to overdo. | 1 |
| C5 | Hover image reveal | Show the project's image under the cursor when I hover its name. | Cheap. Great for indexes of work. | 1 |
| C6 | Pointer-tracked edge glow | Make the card's border glow where the mouse is. | Cheap. The Linear and Vercel card treatment. | — |
| C7 | Image trail | Leave a trail of images along the cursor path. | Cheap. Playful; rarely fits a tool site. | 1 |
| C8 | Cursor-reactive canvas | Make the background particles react to my mouse. | Medium. Throttle and pause off-screen. | 2 |

### P · Particles and generative

Canvas and WebGL systems: dots, fields, shaders, 3D. Expensive; one per page.

| ID | Name | Ask for it | Cost and care | Seen |
| --- | --- | --- | --- | --- |
| P1 | Particle field | Fill the background with slowly drifting dots. | Medium. Cap the count; pause when hidden. | 2 |
| P2 | Constellation network | Connect nearby dots with thin lines that appear around the cursor. | Medium: pair checks grow with count squared. Keep the count low. | — |
| P3 | Particle morph | Have dots fly together to form the logo or a word. | Medium. | — |
| P4 | Starfield warp | Fly through stars. | Medium. Very sci-fi. | — |
| P5 | Flow field | Let particles follow invisible currents that leave trails. | Medium. Beautiful as a still too. | — |
| P6 | Shader gradient | Give the hero a slow, liquid gradient background. | Cheap in CSS, heavier as a WebGL shader. | 6 |
| P7 | Fluid / smoke | Make the cursor leave smoke or ink. | Heavy if real fluid; this demo fakes it. | 1 |
| P8 | Dither / ASCII render | Render the image as characters or dots. | Medium. Fits developer brands well. | 3 |
| P9 | Film grain | Add subtle grain over everything. | Cheap as a static texture. | 2 |
| P10 | 3D scene | Put a real 3D object in the hero that I can spin. | Heavy. Needs a fallback image. | 11 |
| P11 | Physics playground | Let me drag and throw the objects around. | Medium. A toy; give it a reason. | 2 |
| P12 | GPU particle sculpture | Make a shape out of thousands of particles that swirl. | Very heavy. The award-site signature. | — |
| P13 | Beams on connectors | Send light along the lines between nodes when work flows. | Cheap in SVG. | 2 |
| P14 | Dotted globe | Show a rotating dotted globe. | Medium. | — |

### X · Transitions and loading

What happens between states: first paint, navigation, hover swaps.

| ID | Name | Ask for it | Cost and care | Seen |
| --- | --- | --- | --- | --- |
| X1 | Preloader counter | Show a loading screen that counts to 100. | Costs the reader time. Only for heavy WebGL sites. | 7 |
| X2 | Page transition | Wipe or crossfade between pages instead of a hard cut. | Cheap with View Transitions. | 3 |
| X3 | Curtain reveal | Wipe a shape open to reveal the content. | Cheap. | 4 |
| X4 | Image distortion on hover | Ripple the image when I hover it. | Medium; WebGL for the real thing. | 1 |
| X5 | Staged hero load | Bring the hero in piece by piece on first paint: label, headline, copy, command. | Cheap. The page must be complete without it. | 12 |
| X6 | Sound design | Give clicks a soft, quiet sound with a mute toggle. | Cheap. Off by default, always a toggle. | 5 |

### U · Components and patterns

The building blocks of product pages. Ask for these by name.

| ID | Name | Ask for it | Cost and care | Seen |
| --- | --- | --- | --- | --- |
| U1 | Bento grid | Lay the facts out as a grid of different-sized tiles. | Cheap. Use for facts that are numbers. | 6 |
| U2 | Logo wall | Show a strip of customer or tool logos. | Cheap. Real logos only. | 7 |
| U3 | Sliding tab indicator | Slide the underline between tabs. | Cheap. | — |
| U4 | Product replay | Play a scripted demo of the terminal or app. | Cheap. Better than video for crisp text. | 9 |
| U5 | Command palette | Add a Cmd-K search box. | Cheap. Expected on docs sites. | 2 |
| U6 | Command with copy | Put the install command in a pill with a copy button. | Cheap. Essential for CLIs. | 3 |
| U7 | Drag slider with inertia | Make the carousel draggable with momentum. | Cheap. | 1 |
| U8 | Before / after slider | Let me drag a handle to compare two versions. | Cheap. | — |
| U9 | Sticky glass bar | Keep a frosted nav bar on top as I scroll. | Cheap. | 12 |
| U10 | Dock magnification | Grow icons as the mouse passes, like the macOS dock. | Cheap. | — |
| U11 | Feature tabs with media | Clicking a feature swaps the screenshot beside it. | Cheap. | 2 |
| U12 | Live ticker | Show numbers or statuses updating live. | Cheap. Must be real data or labeled as example. | 6 |
| U13 | Glass panels | Use frosted translucent panels over the backdrop. | Cheap. Needs something behind it. | 1 |
| U14 | Dot grid backdrop | Put a faint dot grid behind the content. | Free. | 6 |
| U15 | Comparison table | Compare us against the alternatives, row by capability. | Cheap. Keep it honest. | — |
| U16 | Testimonial wall | Show quotes in a masonry wall. | Cheap. Real quotes only. | 1 |
| U17 | FAQ accordion | Make the questions expand. | Free. | 1 |
| U18 | Explorable diagram | Make the diagram explain itself when I hover a node. | Cheap in SVG. Keyboard-focusable nodes. | — |

### M · Micro-interactions

Small confirmations that make a control feel real.

| ID | Name | Ask for it | Cost and care | Seen |
| --- | --- | --- | --- | --- |
| M1 | Button shine | Pass one sweep of light across the button on hover. | Free. | — |
| M2 | Copy feedback | Confirm the copy on the button itself. | Free. | — |
| M3 | Underline slide | Grow the link underline from left to right on hover. | Free. | 1 |
| M4 | Liveness pulse | Make the status dot breathe while something is running. | Free. Only while work runs. | 3 |
| M5 | Theme toggle morph | Animate the sun into a moon when the theme flips. | Free. | 2 |
| M6 | Tone shift on hover | Brighten the card's surface and edge on hover instead of moving it. | Free. Calmer than lifting. | 3 |

## Part two: design

Static structure: layout, alignment, spacing, hierarchy, composition, the named sections of a page, and colour.

### L · Layout and grid

The skeleton of a page: how wide things are, how many columns, and what sits beside what. Name the layout first; everything else hangs off it.

| ID | Name | What it is | Use it when | Say this, not that |
| --- | --- | --- | --- | --- |
| L1 | 12-column grid | The content width is split into 12 equal columns with gaps (gutters) between them. | Always, as the hidden skeleton. 12 divides into halves, thirds and quarters, so 6+6, 4+4+4 and 7+5 all fit. | "span 7 of 12 columns", not "make it a bit wider" |
| L2 | Content max-width (container) | A container stops text and grids from stretching across very wide screens. Past its cap the page just grows empty margins. | Every page. Pick one cap and reuse it for every section so the edges line up. | "content max-width 1,200 px", not "it looks too spread out on my big monitor" |
| L3 | Full-bleed vs contained | Contained sits inside the container's edges. Full-bleed runs to the edges of the screen, ignoring the container. | Full-bleed for images, colour bands and art that should feel big. Text stays contained so lines stay readable. | "full-bleed image, contained text", not "make the picture bigger" |
| L4 | Split layout | Two columns side by side, usually words in one and a visual in the other. | Any time a sentence needs its picture right next to it. Alternate the image side down the page for rhythm. | "split, image right; on phones text first", not "put them side by side somehow" |
| L5 | Asymmetric split (5:7) | A split where one side is wider, measured in grid columns. Unequal sides feel more designed and give the bigger side the weight. | Section intros (short heading beside a longer paragraph) and text beside a large visual. | "5:7 split, heading left", not "make the left side a bit smaller" |
| L6 | Sidebar plus content | One narrow fixed-width column for navigation or an index, and one fluid column for the content. | Docs, changelogs, settings, long reference pages. |  |
| L7 | Sticky column | One column sticks in place (position: sticky) while its neighbour scrolls. Lighter than full pinning: nothing is hijacked. | A heading or panel that should stay visible while several examples scroll beside it. |  |
| L8 | Centred single column | One narrow column in the middle of the page; every element shares the same centre axis. | Heroes with one message, sign-up pages, essays. Not for long left-aligned reading in a centred alignment. |  |
| L9 | Card grid that reflows | A grid of equal cards whose column count changes with the space available ("3-up" means three per row). | Features, posts, integrations, team members: any list of peers. | "3-up card grid, drops to 1 on phones", not "put them in boxes" |
| L10 | Z-pattern and F-pattern | The path the eye takes. Sparse pages are scanned in a Z; text-heavy pages in an F (across the top, then down the left edge). | Z for heroes and landing pages; F for docs, lists and results, where the left edge must carry the key words. |  |
| L11 | Breakpoints and stacking order | A breakpoint is the screen width where the layout changes. The stacking order says what comes first once columns become rows. | Every multi-column section. Say the breakpoint and the order, or you get whatever the code does. | "at 768 px, stack text then image", not "make it work on mobile" |

### A · Alignment

Which edges and lines things share. Most "it looks off" feelings are an alignment problem you can name.

| ID | Name | What it is | Use it when | Say this, not that |
| --- | --- | --- | --- | --- |
| A1 | Left vs centred alignment | Left-aligned text has one straight edge to return to. Centred text starts every line somewhere new, which is fine for a line or… | Left for anything longer than two lines. Centred for short, symmetric moments: a hero line, a CTA band. |  |
| A2 | Shared left edge | One invisible vertical line that the logo, headlines, paragraphs and cards all start on. | Always. A block starting a few pixels off is the most common reason a page feels sloppy. | "align to the logo's left edge", not "it feels messy" |
| A3 | Optical alignment | Correcting what the eye sees rather than what the box says. A triangle centred by its box looks shifted left; a circle looks… | Icons in buttons, round versus square logos, arrows, quotes. |  |
| A4 | Baseline alignment | Text of different sizes lined up on the line the letters sit on (the baseline), instead of by the middle of their boxes. | Big number plus small unit, heading plus a link on the same row, mixed font sizes in a row. |  |
| A5 | Hanging punctuation | Punctuation at the start of a line (quote marks, bullets) is pushed into the margin so the letters themselves form the straight… | Pull quotes, testimonials, big headlines that start with a quote mark. |  |
| A6 | Align text to an image edge | Text next to or under a picture starts exactly where the picture starts, so the two read as one unit. | Captions, cards, split sections. |  |
| A7 | Visual centre | The eye places the middle of a frame slightly above the geometric middle, so something exactly centred looks low. | Anything alone in a frame: a hero headline, an empty state, a logo on a card. |  |
| A8 | Top vs centre alignment in a row | When a short block sits beside a tall one, you choose whether their tops, middles or bottoms line up. | Top-align text beside tall panels (reads from the top). Centre only short, similar-height items like icons and labels. | "top-align the text with the panel", not "the text is floating" |

### R · Spacing and rhythm

The space between things. Measured numbers from 13 developer sites are in the table further down.

| ID | Name | What it is | Use it when | Say this, not that |
| --- | --- | --- | --- | --- |
| R1 | Spacing scale (4 / 8 px) | A short fixed list of allowed spacing values, nearly all multiples of 8. Every gap and padding picks from it. | Always. It is what makes spacing look intentional instead of eyeballed. | "use 24 from the scale", not "a little more space" |
| R2 | Section padding | The empty space above and below each section's content. It sets the pace of the whole page. | Every section. The median across 13 measured developer sites is 104 px (most fall between 96 and 128). | "section padding 104 px, 80 on phones", not "less spread out" |
| R3 | Vertical rhythm | A consistent pattern of vertical gaps. Small inside a group, larger between groups, largest between sections, repeated everywhere. | Whenever blocks of the same kind look slightly different from each other. | "tighten the vertical rhythm", not "make it less spread out" |
| R4 | Gutters | The gap between columns or cards. In CSS it is gap. | Grids and card rows. Wider gutters read calmer; narrow ones read as one dense unit. |  |
| R5 | Density: compact vs airy | How much fits in one screen. Compact suits tools you scan; airy suits pages you read once. | Compact for tables, logs, dashboards. Airy for landing pages and stories. | "compact density, 32 px rows", not "squeeze it" |
| R6 | Proximity grouping | Things close together read as belonging together. Spacing alone can group, without boxes or lines. | Stats, form labels and fields, captions under images. |  |
| R7 | Whitespace as emphasis | Empty space around something makes it important. Also called negative space. | The one thing on a page you most want read. |  |
| R8 | Padding, gap and margin | Padding is space inside a box, between its edge and its content. Gap is space between boxes. | Any time you describe spacing on a card or panel, say which one you mean. |  |

### H · Hierarchy and type scale

What reads first, second and third, and the type sizes that make it so. Motion of type lives in the Type (T) half.

| ID | Name | What it is | Use it when | Say this, not that |
| --- | --- | --- | --- | --- |
| H1 | Modular type scale | Every font size is the one below it times the same ratio. A small ratio is subtle, a large one dramatic. | Set it once; headings, body and captions all pick from it. | "type scale 1.25", not "make the headings a bit bigger" |
| H2 | Eyebrow (kicker) | A short label set small, often in caps or mono, above a headline. It names the section so the headline can say something bolder. | Section openers. One per section. |  |
| H3 | Display vs body type | Display type is made for big sizes and personality; body type for long reading at small sizes. | Always pick on purpose. A serif display on a developer site stands out because most use one sans. |  |
| H4 | Contrast through size, weight and colour | Three dials make one thing read before another: size, weight and colour. You rarely need all three at once. | Headlines with a claim and a qualifier; lists with a title and detail. |  |
| H5 | Line length (measure) | How many characters fit on one line. 45 to 75 is comfortable; longer lines lose the reader on the way back. | Every paragraph. Set it with a max-width in ch units. | "measure about 65 characters", not "the text is too wide" |
| H6 | Leading (line height) | The vertical distance between lines of text. Body needs room; big headlines need less, or the lines drift apart. | Body 1.5 to 1.7; headlines 0.95 to 1.15. |  |
| H7 | All-caps tracking | Tracking is even letter spacing. Capitals sit too tight by default and need extra; lowercase body text should not get any. | Eyebrows, nav labels, small buttons, table headers. |  |
| H8 | Numbered steps | Index numbers that turn a list into a sequence, so the reader knows where they are and how much is left. | How-it-works sections, setup guides, any real order. |  |
| H9 | Drop cap | An oversized first letter that sinks into the first few lines of a paragraph. It marks the start of long reading. | Essays, about pages, long-form posts. Once per piece. |  |

### K · Arrangement and composition

How elements are placed against each other inside one view: focus, balance, overlap and depth. K for komposition, since C was taken.

| ID | Name | What it is | Use it when | Say this, not that |
| --- | --- | --- | --- | --- |
| K1 | One focal point per view | In each screenful, one element is clearly the thing to look at. Everything else is quieter in size, colour or contrast. | Every view. If two things shout, neither is heard. | "one focal point: the product window", not "make everything pop" |
| K2 | Rule of thirds | Split the frame into a 3 by 3 grid; subjects placed on the lines or their crossings feel more alive than dead centre. | Hero images, photography, a single object in a big frame. |  |
| K3 | Layering and overlap | One element partly covers another. It ties them together and adds depth that a neat side-by-side never has. | Hero headline and image, cards over a backdrop, a screenshot over a painting. |  |
| K4 | Depth | Fake distance on a flat screen using scale, blur, shadow and overlap. | Product shots and stacked windows. Not on every card. |  |
| K5 | Framing | A border, brackets or window chrome around something so it reads as an object to look at, like a figure in a paper. | Diagrams, product visuals, the one thing in a section that deserves attention. |  |
| K6 | Repetition and rhythm | Repeating the same shape and placement makes a set read as a set and lets the content be the difference. | Card grids, logo rows, step lists. |  |
| K7 | Breaking the grid on purpose | Once everything follows the grid, one deliberate exception draws the eye. Too many exceptions read as mess. | Once or twice a page, on the element you most want noticed. |  |
| K8 | Contrast of scale | A big jump between the largest and the smallest element. Drama comes from the gap, not from either size. | Heroes and section openers that should feel confident. |  |
| K9 | Balance: symmetric vs asymmetric | Symmetric layouts mirror around the centre and feel calm. Asymmetric ones balance unequal weights and feel dynamic. | Symmetric for formal, centred moments. Asymmetric for most product sections. |  |

### V · Section and component vocabulary

The named building blocks of a landing page. Ask for them by name and say which variant.

| ID | Name | What it is | Use it when | Say this, not that |
| --- | --- | --- | --- | --- |
| V1 | Centred hero | The first screen with everything stacked on the centre axis. | One clear message and one action. Weak if you need to show the product immediately. |  |
| V2 | Split hero | The first screen as a split layout: words on one side, a visual on the other. | The visual matters as much as the words. |  |
| V3 | Product-shot hero | A short headline above a big, faithful screenshot or live recreation of the product. | The product is the proof. The crop at the fold invites scrolling. |  |
| V4 | Announcement bar | A slim full-width strip at the very top for one piece of news. The pill version sits above the headline instead. | Launches and events, for a few weeks. Remove it after. |  |
| V5 | Stats row | A row of big numbers, each with a short caption saying what it counts. | The numbers are real, specific and impressive. Three or four, no more. |  |
| V6 | Feature grid | A grid of equal cells, each one capability with a small visual, a title and a sentence. | Summarising several capabilities at the same level. Use a bento (U1) when one matters more. |  |
| V7 | How-it-works steps | A short sequence explaining the process, each step a number, a title and a small proof (code, a screenshot). | People need the order of things to trust the product. |  |
| V8 | Pricing tiers | Side-by-side plan cards: name, price, what is included, one button each. One plan is visually raised. | Any self-serve pricing page. |  |
| V9 | Testimonial (quote card) | A real customer quote with the person attached. One strong quote beats a wall of weak ones. | Right after a claim it backs up. |  |
| V10 | CTA band | A call-to-action strip near the end of a page that repeats the main action. | Bottom of every landing page, before the footer. |  |
| V11 | Footer: mega vs minimal | A mega footer is a site map in columns; a minimal footer is one line of essentials. | Mega for sites with many pages; minimal for single-product pages. |  |
| V12 | Nav: transparent to solid | The top bar sits invisibly on the hero art, then gains a background once content would pass under it. | Heroes with full-bleed art. A sticky secondary nav (section links) can sit under it. |  |
| V13 | Card styles | Four ways to make a card: outlined (a border), elevated (a shadow), glass (blurred translucent) and tonal (a slightly different… | Pick one style for the whole site. Mixing them reads as unfinished. |  |
| V14 | Badges and pills | Small rounded labels for status, counts, tags and keyboard keys. | Statuses, "New" markers, filters, shortcut hints. |  |
| V15 | Segmented control | A row of two to four joined buttons where exactly one is selected. Lighter than tabs. | Switching a view or a unit in place: billing period, list vs board. |  |
| V16 | Toast vs banner | A toast is a small temporary message that floats in a corner. A banner is a full-width message in the page that stays until… | Toast for confirmations. Banner for things the reader must act on. |  |
| V17 | Dialog and drawer | A dialog (modal) is a centred box over a dimmed page. A drawer slides in from an edge and keeps the page visible beside it. | Dialog for a decision. Drawer for details you compare with the page. |  |
| V18 | Peek carousel | A horizontally scrolling row where the cut-off card at the edge signals there is more. | Galleries and examples on phones, where a grid would be too long. |  |

### F · Colour and surface

Colour roles, surfaces and how panels separate from each other. F for fill.

| ID | Name | What it is | Use it when | Say this, not that |
| --- | --- | --- | --- | --- |
| F1 | Neutral ramp | A ladder of greys from near-white to near-black. Backgrounds, borders and text all pick from it. Warm or cool greys set the mood. | First thing in any palette. Most of a page is neutrals. |  |
| F2 | One accent colour | One saturated colour against neutrals. Because it is rare, it marks what to click. | Almost always. Status colours (green, amber, red) are separate and only mean status. | "one accent, for actions only", not "make it more colourful" |
| F3 | Text colour roles | Named roles instead of hex codes, so hierarchy is consistent and dark mode can swap them. | Every page. Two or three roles, not seven greys. |  |
| F4 | Elevation: border vs shadow | How a surface separates from what is behind it: a border (flat, technical), a shadow (lifted, soft) or a tonal fill (quiet). | Borders for dense technical UIs and dark themes. Shadows for floating things: menus, dialogs. |  |
| F5 | Gradients | A blend between colours. A wash is barely visible; a mesh or ribbon is the star; a text gradient tints the letters. | A wash almost anywhere. A bold gradient once per page at most. |  |
| F6 | Light and dark themes | Two palettes built from the same roles. The accent usually needs a different shade in each to keep contrast. | Developer audiences expect dark. Offer both if you can keep both polished. |  |
| F7 | Contrast (WCAG AA) | The brightness ratio between text and its background. Below 4.5 to 1, small text gets hard to read for many people. | Every grey you add, in both themes. |  |
| F8 | Tonal band | A full-width section on a slightly different background tone, so the page has chapters without lines or boxes. | Separating a section that changes subject, like proof or pricing. |  |
| F9 | Hairline rules | Thin 1 px lines between areas. They divide without adding weight, and read as precise and technical. | Developer and infrastructure sites, tables, feature rows. |  |

## Spacing, measured

Live measurements of developer sites at 1440 x 900. Median section padding across the measured sites is about 104 px, mostly 96 to 128 px. No site bounces its hover; reveals are opacity plus a 10 to 20 px rise.

| Site | Section padding | Content width | Hover timing |
| --- | --- | --- | --- |
| [Linear](https://linear.app/) | 128 px | 1,320 to 1,344 px | 100 to 160 ms |
| [Stripe](https://stripe.com/) | 80 to 123 px | 1,266 px (inner) | 300 ms |
| [Resend](https://resend.com/) | 96 px | 1,280 px | 150 to 200 ms |
| [Framer](https://www.framer.com/) | 120 px | 1,200 px | Framer Motion |
| [Tines](https://www.tines.com/) | 96 px | 1,232 px | 300 ms |
| [Cursor](https://cursor.com/) | 67 px | 1,300 px | 150 ms |
| [Clerk](https://clerk.com/) | 128 / 172 px | 1,264 px | 300 ms |
| [Modal](https://modal.com/) | 144 px | 1,312 px | 150 ms |
| [Raycast](https://www.raycast.com/) | 224 px | 1,204 px | 200 to 300 ms |
| [Antimetal](https://antimetal.com/) | 80 px | 1,512 px (wrapper) | 200 to 300 ms |

## Named in the wild

Patterns the research found that the standard vocabulary above does not cover. Ask for them by these names.

| Name | What it is | Seen on |
| --- | --- | --- |
| Hud overlay | Small monospace labels, coordinates and grid lines framing a hero visual like a heads-up display. | Igloo Inc., KPR (kprverse) |
| Mode switch | A switch that turns the whole page into another mode: plain vs rich, or human vs machine-readable. | Shopify Editions Winter '25, basement.studio |
| Kbd hints | Each button shows its keyboard key, and the key works (D to download, C to copy). | Warp, Zed |
| Live cell grid | A grid of cells that light up as live work happens; each cell is one running job. | Warp |
| Text frame animation | Animation made of pre-baked text frames, like ASCII art flipping in a terminal. | Ghostty |
| Source to render | Input on the left, result on the right, scroll walks through which part produced which. | Artifacts by Phoenix (baseline) |
| Mega menu | A large nav dropdown with grouped links and previews. | Linear, Vercel, Cursor |
| Focus desaturate | Everything is grayscale except the item in focus, which turns to color. | Obys Agency, Aristide Benoist |
| Focus frame | A fixed lens or bracket the content scrolls through; the item inside it is selected. | Obys Agency |
| Blueprint to render | The product first appears as a wireframe drawing, then fills in to the real thing. | ORYZO |
| Graceful unsupported | A designed fallback screen when WebGL or the browser is not supported. | Active Theory |
| Contextual cursor | The cursor changes into a labeled control (play, copy, open) over regions. | Cuberto |
| Glow input | The product's own input box is the hero, with a glowing edge inviting you to type. | Framer |
| Glyph swap | One letter or word in the headline keeps cycling through alternatives. | GSAP |
| Entry gate | An Enter or Begin button the visitor presses before the experience starts. | Unseen Studio |
| Figure captions | Product visuals labeled like figures in a paper (fig. 1, fig. 2). | Warp |
| Customer proof panel | Each customer story pairs a real screenshot with one hard number. | Vercel |
| Light beam | A soft diagonal beam of light across the hero. | Resend |
| Painted backdrop | Product screenshots set on a painting or photograph instead of a flat color. | Cursor |
