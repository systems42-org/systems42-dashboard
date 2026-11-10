---
type: metamodel
construct: relation
name: primary-actor
aliases: [rel-primary-actor]
field: primary-actor
direction: directed
semantics: actor
inverse: use-cases
inverse_stored: false
reciprocity: none
edges:
  - {from: use-case, to: stakeholder, cardinality: "1"}
---

# Relation: primary actor

The one stakeholder whose goal the use case is. Supporting actors stay prose links.
A stakeholder with no inbound `primary-actor` and no FR mention is a coverage gap
(inspect).
