---
type: metamodel
construct: relation
name: actors
aliases: [rel-actors]
field: actors
direction: directed
semantics: actor
inverse: activities
inverse_stored: false
reciprocity: none
edges:
  - {from: activity-model, to: stakeholder, cardinality: "1..*"}
---

# Relation: actors

The roles that take part in a process.
