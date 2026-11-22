---
type: metamodel
construct: relation
name: realizes
aliases: [rel-realizes]
field: realizes
direction: directed
semantics: serves
inverse: realized-by
inverse_stored: false
reciprocity: none
edges:
  - {from: runtime-scenario, to: functional-requirement, cardinality: "0..*"}
  - {from: runtime-scenario, to: activity-model, cardinality: "0..*"}
---

# Relation: realizes

The requirement or process a runtime scenario carries out; the bridge from
the runtime view back to the requirements, so the flow is not written twice.
