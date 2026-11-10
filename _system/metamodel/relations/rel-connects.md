---
type: metamodel
construct: relation
name: connects
aliases: [rel-connects]
field: connects
direction: directed
semantics: communication
inverse: connected-from
inverse_stored: false
reciprocity: none
edges:
  - {from: deployment-node, to: deployment-node, cardinality: "0..*", note: "structured entries {to, protocol?, note?}, stored on the initiating side"}
  - {from: deployment-node, to: external-interface, cardinality: "0..*"}
---

# Relation: connects

A channel between nodes (or to an external system), labelled with its protocol in
the [[proj-deployment-diagram]].
