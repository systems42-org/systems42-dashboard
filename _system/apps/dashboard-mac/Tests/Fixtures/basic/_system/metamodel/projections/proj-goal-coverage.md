---
type: metamodel
construct: projection
name: goal-coverage
aliases: [proj-goal-coverage]
reads:
  - {type: functional-requirement, fields: [notation, level, goal, lane]}
  - {type: goal, fields: [stereotype]}
output: matrix
stored: false
implemented: "/goals (covering-epic counts)"
anchor: story-mapping
decision: DR-018-projections-from-typed-edges
---

# Projection: goal coverage

Objectives × epics, from [[rel-goal]]. An objective no epic serves is a gap; a
backbone epic with `goal: []` is a rule violation ([[rule-fr-traces-to-goal]]).
