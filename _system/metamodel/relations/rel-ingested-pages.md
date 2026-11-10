---
type: metamodel
construct: relation
name: ingested-pages
aliases: [rel-ingested-pages]
field: ingested-pages
direction: directed
semantics: provenance
inverse: sources
inverse_stored: true
inverse_field: sources
reciprocity: none
edges:
  - {from: source, to: any, cardinality: "0..*"}
---

# Relation: ingested pages

The reverse of [[rel-sources]], maintained by capture. Keeps the historical name
"ingested" on purpose (the workflow was renamed to capture, the field was not).
