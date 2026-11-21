---
type: metamodel
construct: relation
name: owner
aliases: [rel-owner]
field: owner
direction: directed
semantics: actor
inverse: owns
inverse_stored: false
reciprocity: none
edges:
  - {from: issue, to: stakeholder, cardinality: "0..1", note: "a stakeholder link only, no literal; empty means not yet clear who can answer"}
---

# Relation: owner

The stakeholder an Issue's question is addressed to: the one whose answer
resolves it. Usually a stakeholder group, not a person. There is no due date:
the wiki is not a project management tool. Counterpart of [[rel-raised-by]],
which says who put the question on the table.
