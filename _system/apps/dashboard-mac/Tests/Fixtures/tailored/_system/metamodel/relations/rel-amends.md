---
type: metamodel
construct: relation
name: amends
aliases: [rel-amends]
field: amends
direction: directed
semantics: revision
inverse: amended-by
inverse_stored: false
reciprocity: none
edges:
  - {from: decision-record, to: decision-record, cardinality: "0..*", note: "this record changes some points of the target, which stays in force"}
---

# Relation: amends

A later decision that changes part of an earlier one. The earlier record stays
`accepted`; its readers follow the inverse, which the dashboard projects.
