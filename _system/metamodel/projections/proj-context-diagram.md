---
type: metamodel
construct: projection
name: context-diagram
aliases: [proj-context-diagram]
reads:
  - {type: external-interface, fields: [partner, short_title, tier, flows, status]}
  - {type: stakeholder, fields: [provides, receives, nature, context_role]}
  - {type: context, fields: [kind]}
output: mermaid
stored: false
implemented: "/req42/scope"
anchor: req42
decision: DR-013-data-flows-as-edges-context-diagram-as-projection, DR-014-context-diagram-actor-roles-and-shapes, DR-026-context-diagram-captured-as-drawn
---

# Projection: context diagram

Projected from edges, never stored: EIF `flows` for systems, STK `provides` /
`receives` for human roles. Deprecated interfaces are drawn nowhere. "No drift by
construction" — inspect only checks that the edges are consistent.
