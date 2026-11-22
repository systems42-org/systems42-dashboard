---
type: metamodel
construct: relation
name: primary-actor
aliases: [rel-primary-actor]
field: primary-actor
direction: directed
semantics: actor
inverse: functional-requirements
inverse_stored: false
reciprocity: none
edges:
  - {from: functional-requirement, to: stakeholder, cardinality: "1", note: "for notation: use-case"}
---

# Relation: primary actor

The one stakeholder whose goal a Cockburn use-case requirement is. Supporting
actors stay prose links. A stakeholder with no inbound `primary-actor` and no FR
mention is a coverage gap (inspect).
