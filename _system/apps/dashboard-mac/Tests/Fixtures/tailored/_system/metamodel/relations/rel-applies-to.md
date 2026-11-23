---
type: metamodel
construct: relation
name: applies-to
aliases: [rel-applies-to]
field: applies-to
direction: directed
semantics: association
inverse: governed-by
inverse_stored: false
reciprocity: none
edges:
  - {from: crosscutting-concept, to: building-block, cardinality: "0..*"}
  - {from: crosscutting-concept, to: deployment-node, cardinality: "0..*"}
---

# Relation: applies to

The blocks and nodes a crosscutting concept governs. Empty means the whole
system. The inverse is projected onto their pages ([[proj-governed-by]]).
