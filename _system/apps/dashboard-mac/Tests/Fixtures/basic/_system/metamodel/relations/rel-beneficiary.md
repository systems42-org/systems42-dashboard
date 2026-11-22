---
type: metamodel
construct: relation
name: beneficiary
aliases: [rel-beneficiary]
field: beneficiary
direction: directed
semantics: beneficiary
inverse: benefits-from
inverse_stored: false
reciprocity: none
edges:
  - {from: goal, to: stakeholder, cardinality: "0..*", note: "PAM Advantage: who gets the benefit"}
---

# Relation: beneficiary

Who a goal is for. Feeds the stakeholder matrix report; not drawn anywhere yet.
