---
type: metamodel
construct: relation
name: relationships
aliases: [rel-relationships]
field: relationships
direction: directed
semantics: structure
inverse: referenced-by
inverse_stored: false
reciprocity: none
edges:
  - {from: domain-term, to: domain-term, cardinality: "0..*", note: "both terms carry a stereotype"}
---

# Relation: relationships

Each entry has a target (`to`), a `kind`, an optional `label` and an optional
target-end `multiplicity`. Generalization omits multiplicity. See [[proj-entity-diagram]].
