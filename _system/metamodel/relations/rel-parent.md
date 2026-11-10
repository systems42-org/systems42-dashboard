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
  - {from: functional-requirement, to: functional-requirement, cardinality: "0..*", note: "story → feature → epic; several parents make it a graph, the dashboard draws the first (DR-012)"}
  - {from: functional-requirement, to: use-case, cardinality: "0..*", note: "feature or story refining a use case, e.g. one of its alternate flows; never an epic (DR-011)"}
  - {from: goal, to: goal, cardinality: "0..1", note: "objective → vision (DR-016)"}
  - {from: data-model, to: data-model, cardinality: "0..1", note: "sum-type variant → sum-type (DR-019)"}
  - {from: building-block, to: building-block, cardinality: "0..1", note: "block → enclosing block (arc42 levels)"}
  - {from: building-block, to: context, cardinality: "0..1", note: "level-1 block → the system's context page"}
  - {from: deployment-node, to: deployment-node, cardinality: "0..1", note: "node → enclosing node (infrastructure levels)"}
---

# Relation: parent

The hierarchy edge, reused by several types with the same meaning: *coarser item*.
"Children" is never stored; the [[proj-goal-tree]], the FR breakdown and the
[[proj-story-map]] project it.

A feature or story may name a **use case** as its parent
(DR-011): both are functional
requirements, so a use case can be broken down like an epic. An epic never sits
under a use case, and a use case never names a parent: how use cases and epics
compare stays open ([[altitude]]). The use case's "Realized by" list is this
edge projected backwards, never stored.
