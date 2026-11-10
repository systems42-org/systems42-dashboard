---
type: metamodel
construct: type
name: constraint
aliases: [type-constraint, CON]
prefix: CON
folder: wiki/constraints
template: _templates/constraint.md
label: Constraint
label_de: Randbedingung
block: C2
lifecycle: content
stereotypes: []
naming: "constraint summary"
fields:
  - {name: category, kind: enum, values: [technical, organizational, legal, political, economic]}
anchors: [req42]
projections: []
---

# Type: constraint

req42 block 07: a limit on the solution space imposed from outside. Shared with
arc42 (commons block C2).
