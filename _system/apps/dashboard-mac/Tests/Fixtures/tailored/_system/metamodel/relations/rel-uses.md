---
type: metamodel
construct: relation
name: uses
aliases: [rel-uses]
field: uses
direction: directed
semantics: dependency
inverse: used-by
inverse_stored: false
reciprocity: none
edges:
  - {from: building-block, to: building-block, cardinality: "0..*"}
  - {from: building-block, to: external-interface, cardinality: "0..*", note: "a neighbour system, drawn outside the white box"}
---

# Relation: uses

A static dependency: this block needs that block or that external system. The
arrows of the [[proj-whitebox]] and of the level-1 overview.
