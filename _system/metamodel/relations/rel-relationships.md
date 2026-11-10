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
  - {from: data-model, to: data-model, cardinality: "0..*", note: "structured entries {verb, target, cardinality, kind ∈ association|aggregation|composition|inheritance, mandatory}; a dangling target is dropped from the diagram (DR-027)"}
---

# Relation: relationships

The only relation whose entries carry attributes of their own (verb, kind,
cardinality at the target end). Read by [[proj-data-model-diagram]].
