---
type: metamodel
construct: type
name: stakeholder
aliases: [type-stakeholder, STK]
prefix: STK
folder: wiki/stakeholders
template: _templates/stakeholder.md
label: Stakeholder
label_de: Stakeholder
block: C4
lifecycle: content
stereotypes: []
naming: "role or persona name"
fields:
  - {name: aliases, kind: list, doc: "other names, incl. former titles"}
  - {name: role, kind: scalar}
  - {name: influence, kind: enum, values: [high, medium, low]}
  - {name: interest, kind: enum, values: [high, medium, low]}
  - {name: provides, kind: list, doc: "data this role supplies into the system — inbound context edges (DR-013)"}
  - {name: receives, kind: list, doc: "data this role gets from the system — outbound context edges"}
  - {name: nature, kind: enum, values: [person, organization], doc: "context-diagram shape"}
  - {name: context_role, kind: scalar, doc: "diagram label / merge key; `none` hides the node"}
anchors: [req42]
projections: [context-diagram]
sort_orders:
  - {label: "Influence › interest", keys: [influence, interest]}
---

# Type: stakeholder

A simplified persona: goals, concerns, influence × interest. Stakeholders are also
the **human actors of the context diagram**: their `provides` / `receives` lists are
edges the [[proj-context-diagram]] reads, which is why human channels are *not*
external interfaces (DR-013). Target of [[rel-primary-actor]], [[rel-actors]] and
[[rel-beneficiary]].
