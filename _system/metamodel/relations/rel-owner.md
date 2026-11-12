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
  - {from: issue, to: stakeholder, cardinality: "0..1", note: "or a person's name, like raised-by. Empty means nobody yet"}
---

# Relation: owner

Who is expected to answer the question. There is no due date: the wiki is not a
project management tool (FR-028).
