---
type: metamodel
construct: rule
name: fr-traces-to-goal
aliases: [rule-fr-traces-to-goal]
applies_to: {type: functional-requirement, stereotype: [epic, feature]}
check: "`goal` is non-empty, or `parent` is a use case with goals, or `lane` is platform | display (an explicit enabler)"
confidence: medium
action: issue
source: "_system/anchors/story-mapping.md checklist; DR-018"
---

# Rule: a backbone epic or feature traces to a goal

Advisory: raise an `ISS-NNN`, never fill `goal` in. A feature under a use case
traces through the use case's `goal:` (DR-011). Goal coverage
([[proj-goal-coverage]]) is only as good as this edge.
