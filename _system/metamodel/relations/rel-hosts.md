---
type: metamodel
construct: relation
name: hosts
aliases: [rel-hosts]
field: hosts
direction: directed
semantics: deployment
inverse: deployed-on
inverse_stored: false
reciprocity: none
edges:
  - {from: deployment-node, to: building-block, cardinality: "0..*"}
---

# Relation: hosts

Maps building blocks onto infrastructure: "this block runs on that node". The
inverse, *deployed on*, is projected onto block pages.
