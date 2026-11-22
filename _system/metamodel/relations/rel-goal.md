---
type: metamodel
construct: relation
name: goal
aliases: [rel-goal]
field: goal
direction: directed
semantics: serves
inverse: covered-by
inverse_stored: false
reciprocity: none
edges:
  - {from: functional-requirement, to: goal, cardinality: "0..*", note: "[] is an explicit enabler (lane platform/display), not a gap — unless the item is backbone"}
---

# Relation: goal

"This requirement serves that goal." Source of the [[proj-goal-coverage]] matrix
(DR-018). A backbone epic or feature with `goal: []` is a rule violation; a
platform item with `goal: []` is an enabler.
