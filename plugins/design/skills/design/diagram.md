# Diagram design

Create or refine diagrams of structures,
relationships, processes, or interactions using the actual system and its evidence.

1. Establish the question, audience, and scope. Inspect existing diagrams and trace the
   relevant source or observed behavior; label proposed structure separately from reality.
2. Use the notation the field already has, so an expert recognizes it at a glance:
   C4 for architecture (one abstraction level per figure, every arrow labeled with what
   flows and the protocol, a legend), UML sequence for message order (solid line and filled
   head = sync call, open head = async, dashed = reply), crow's-foot ER for data models,
   ISO 5807 flowcharts for control flow (diamond decisions with every branch labeled),
   swimlanes for handoffs between actors. Keep one notation, one flow direction, a type on
   every node, and a legend whenever color or line style carries meaning.
3. Reuse the product's visual conventions. Label relationships, direction, and what
   passes between elements; add a legend where color or line style encodes meaning.
4. Use a suitable diagram medium. A small Mermaid figure may suffice; use an inspected
   artifact with editable SVG/HTML when layout or presentation needs more control.
   Do not replace an existing editable diagram with a disconnected drawing without reason.
5. Inspect the rendered result for correctness, clipping, readability, and clear
   relationships. Verify navigation or interaction if present. Deliver through the
   shared artifact and presentation guidance.

Quantitative axes and data stories belong in `dataviz.md`; interactive product screens
belong in `design:prototype`.
