---
type: metamodel
construct: relation
name: related
aliases: [rel-related]
field: related
direction: symmetric
semantics: association
inverse: related
inverse_stored: true
inverse_field: related
reciprocity: enforced
edges:
  - {from: any, to: any, cardinality: "0..*", note: "same-slug pages of different types may represent the same concept across views"}
---

# Relation: related

The one **symmetric** relation. Because it is symmetric, the relations linter may
repair a missing back-link on its own (tiers 1–2 of `relations.md`); every other
relation is directed and its reverse is projected or capture-maintained.
