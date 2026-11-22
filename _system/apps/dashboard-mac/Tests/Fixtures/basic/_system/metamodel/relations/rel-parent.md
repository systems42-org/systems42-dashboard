---
type: metamodel
construct: relation
name: parent
aliases: [rel-parent]
field: parent
direction: directed
semantics: hierarchy
inverse: children
inverse_stored: false
reciprocity: none
edges:
  - {from: functional-requirement, to: functional-requirement, cardinality: "0..*", note: "story → feature → epic; a feature or story may also name a sea- or fish-level use case (DR-038 amendment); several parents make it a graph, the dashboard draws the first (DR-012)"}
  - {from: goal, to: goal, cardinality: "0..1", note: "objective → vision (DR-016)"}
  - {from: domain-term, to: domain-term, cardinality: "0..1", note: "sum-type variant → sum-type (DR-019)"}
  - {from: building-block, to: building-block, cardinality: "0..1", note: "block → enclosing block (arc42 levels)"}
  - {from: building-block, to: context, cardinality: "0..1", note: "level-1 block → the system's context page"}
  - {from: deployment-node, to: deployment-node, cardinality: "0..1", note: "node → enclosing node (infrastructure levels)"}
---

# Relation: parent

The hierarchy edge, reused by three types with the same meaning: *coarser item*.
"Children" is never stored; the [[proj-goal-tree]], the FR breakdown and the
[[proj-story-map]] project it.
