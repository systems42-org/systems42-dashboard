---
type: metamodel
construct: rule
name: fr-traces-to-goal
aliases: [rule-fr-traces-to-goal]
applies_to: {type: functional-requirement, notation: agile, level: [epic, feature]}
check: "`goal` is non-empty, or `lane` is platform | display (an explicit enabler), or the first `parent` is a use case with non-empty `goal` (the feature serves the use case's goals)"
confidence: medium
action: issue
source: "_system/anchors/story-mapping.md checklist; DR-018"
---

# Rule: a backbone epic or feature traces to a goal

Advisory: raise an `ISS-NNN`, never fill `goal` in. Goal coverage
([[proj-goal-coverage]]) is only as good as this edge.

A feature that refines a use case (DR-038 amendment) with `goal: []` serves
that use case's goals; it is no enabler and no violation.
