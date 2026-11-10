---
type: metamodel
construct: type
name: external-interface
aliases: [type-external-interface, EIF]
prefix: EIF
folder: wiki/external-interfaces
template: _templates/external-interface.md
label: External interface
label_de: Externe Schnittstelle
block: C3
lifecycle: content
stereotypes: []
naming: "interface / neighbour name"
fields:
  - {name: partner, kind: scalar, doc: "the neighbouring SYSTEM; human roles are stakeholders, not EIFs (DR-013)"}
  - {name: tier, kind: enum, values: [supply, support, demand, core-operations], required: false, doc: "band of the diagram (DR-026)"}
  - {name: short_title, kind: scalar, doc: "short node label"}
  - {name: flows, kind: structured-list, doc: "{data, direction, format, trigger, label} — one per data flow; the context-diagram edges"}
anchors: [req42]
projections: [context-diagram]
---

# Type: external interface

One neighbour system per node; its `flows` are the edges of the
[[proj-context-diagram]]. Both directions of a neighbour draw one line (DR-026).
