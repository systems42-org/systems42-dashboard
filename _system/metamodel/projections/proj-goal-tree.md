---
type: metamodel
construct: projection
name: goal-tree
aliases: [proj-goal-tree]
reads:
  - {type: goal, fields: [stereotype, parent, short_title, tile_claim]}
  - {type: functional-requirement, fields: [stereotype, goal]}
output: mermaid
stored: false
implemented: "/goals and /req42/functional-requirements"
anchor: PAM
decision: DR-016-goals-content-type
---

# Projection: goal tree

Vision → objectives from [[rel-parent]]; the goal/epic map on the functional-
requirements page extends it one level down through [[rel-goal]].
