---
type: metamodel
construct: relation
name: applies-to
aliases: [rel-applies-to]
field: applies-to
direction: directed
semantics: application
inverse: governed-by
inverse_stored: false
reciprocity: none
edges:
  - {from: concept, to: building-block, cardinality: "0..*"}
  - {from: concept, to: deployment-node, cardinality: "0..*"}
---

# Relation: applies to

"This concept governs that block or node." Empty means the whole system. The
inverse, *governed by*, is projected onto block and node pages ([[proj-governed-by]]).
