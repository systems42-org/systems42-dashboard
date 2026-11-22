---
type: metamodel
construct: type
name: context
aliases: [type-context, CTX]
prefix: CTX
folder: wiki/context
template: _templates/context.md
label: Context
label_de: Kontext
block: C3
lifecycle: content
stereotypes: []
naming: "system context name"
fields:
  - {name: kind, kind: enum, values: [business, technical]}
  - {name: diagram, kind: scalar, doc: "always `generated`: the diagram is projected from EIF.flows and STK.provides/receives, never stored (DR-013)"}
anchors: [req42]
projections: [context-diagram]
---

# Type: context

req42 block 03, the scope node: boundary, in / out of scope, user roles, external
interfaces. The context diagram is a [[proj-context-diagram|projection]]; this page
owns the prose and the non-goals, not the picture.
