# Diagram conventions — draw figures a domain expert recognizes

Referenced by `plan-render` and `visualize`. When a figure depicts a structure that a
field already has a standard notation for, **use that notation** instead of ad-hoc boxes
and arrows. The test: a professional in that field glances at the figure and recognizes it
immediately. Add a **legend** whenever color or line-style carries meaning.

## Pick the notation by what the figure shows

| The figure shows | Use | The detail that signals you know it |
|---|---|---|
| System / service architecture | **C4** (Context → Container → Component) | one abstraction level per diagram; a legend is mandatory; every arrow labeled with *what flows* + protocol |
| Message ordering between parties | **UML sequence** | lifelines (dashed verticals) + activation bars; **filled arrowhead = sync call, dashed open arrowhead = return**; time flows top-down |
| Object / type relationships | **UML class** | inheritance = hollow triangle to the parent; composition = filled diamond; aggregation = hollow diamond; multiplicity at both line ends |
| Data model / tables | **ER, crow's-foot** | cardinality glyphs at the entity end (bar = one, fork = many, circle = optional); mark PK / FK |
| Data movement through a system | **DFD** | process = numbered verb; data store = open-ended rectangle; external entity = square; every flow is a **named noun**, never control ("then", "click") |
| Control flow / algorithm | **flowchart, ISO 5807 shapes** | oval = start/end, rectangle = process, **diamond = decision (label every branch)**, parallelogram = I/O |
| Business / multi-actor process | **BPMN** | event circles (thin border = start, bold = end), rounded-rect tasks, diamond gateways with an X/+/O marker; solid sequence flow stays in a pool, dashed message flow crosses pools |
| Network / cloud topology | **provider icon set + boundaries** | one provider's official icons (AWS / GCP / Azure), wrapped in VPC / subnet / zone boxes; draw trust boundaries; label ports and protocols on links |
| Schedule / dependencies over time | **Gantt / swimlane** | bars = duration, diamonds = milestones, dependency arrows, critical path marked; each task sits in its owner's lane |
| Quantitative data | **the chart that fits the data** (see below) | axes labeled with units; no chartjunk |

## Non-software fields — use the field's own standard

- **Electrical** — IEC 60617 *or* ANSI/IEEE 315 symbols, never mixed. Power systems use a
  **single-line diagram** with IEEE C37.2 device numbers on protection (50/51, 87, 52).
- **Process / chemical** — **P&ID** per ANSI/ISA-5.1: instrument bubbles carry a tag (first
  letter = measured variable, e.g. F/T/P/L; a line through the bubble encodes mounting
  location; a circle-in-square is a shared DCS/SCADA function).
- **Scientific / quantitative** — Tufte discipline (below).

## Charts (quantitative figures)

- **Match the chart to the data shape.** Categorical comparison → bar (y-axis from 0);
  trend over time → line; distribution → histogram or box; correlation → scatter;
  part-to-whole → stacked bar (not a pie beyond ~3 slices); two-variable field → heatmap.
- **Label every axis with quantity + units.** Direct-label each series at its end rather
  than forcing a legend round-trip.
- **Delete chartjunk:** no 3-D, no gradients or shadows, no heavy gridlines, no rainbow/jet
  colormap.
- **Colorblind-safe palettes:** categorical → **Okabe-Ito**; sequential → **Viridis**.
  Never encode meaning by red-vs-green alone; pair color with shape or line-style.

## The amateur tells (avoid these)

- Everything is a plain rectangle joined by unlabeled arrows.
- A decision drawn as a box instead of a diamond; I/O as a box instead of a parallelogram.
- Sync call, async call, and return all drawn with the same arrowhead.
- Cardinality written as free text ("1:N") instead of the crow's-foot glyphs.
- Two notations mixed in one diagram (IEC + ANSI, AWS + GCP, Chen + crow's-foot), or two
  abstraction levels in one C4 diagram.
- Color used to mean something, with no legend.

## Five cheap moves that read as professional

1. One notation, one abstraction level per diagram.
2. One consistent flow direction (top-down or left-to-right).
3. Every arrow says *what flows* (and, for architecture, how — the protocol).
4. Every node states its type; every axis carries units.
5. A **legend** whenever color or line-style encodes meaning (mandatory for C4).

Sources: C4 (c4model.com), UML 2.5.1 (OMG), BPMN 2.0.2 / ISO 19510, ANSI/ISA-5.1-2024,
IEC 60617 / IEEE 315, Okabe-Ito & Viridis palettes.
