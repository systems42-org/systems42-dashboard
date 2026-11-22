---
type: metamodel
construct: relation
name: hosts
aliases: [rel-hosts]
field: hosts
direction: directed
semantics: structure
inverse: deployed-on
inverse_stored: false
reciprocity: none
edges:
  - {from: deployment-node, to: building-block, cardinality: "0..*"}
---

# Relation: hosts

The mapping of software to infrastructure: the building blocks deployed on a node.
