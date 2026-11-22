---
type: metamodel
construct: relation
name: sources
aliases: [rel-sources]
field: sources
direction: directed
semantics: provenance
inverse: ingested-pages
inverse_stored: true
inverse_field: ingested-pages
reciprocity: none
edges:
  - {from: any, to: source, cardinality: "0..*", note: "empty sources and no [!assumption] ⇒ inspect raises an Issue"}
---

# Relation: sources

Provenance: every derived claim links the source it came from. The reverse list,
[[rel-ingested-pages]], is written by the capture workflow (step 5), not by the
linter — a directed relation whose inverse happens to be stored.
