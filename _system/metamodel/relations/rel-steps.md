---
type: metamodel
construct: relation
name: steps
aliases: [rel-steps]
field: steps
direction: directed
semantics: interaction
inverse: takes-part-in
inverse_stored: false
reciprocity: none
edges:
  - {from: runtime-scenario, to: building-block, cardinality: "0..*", note: "structured entries {from, to, message, note?}, in order"}
  - {from: runtime-scenario, to: external-interface, cardinality: "0..*"}
  - {from: runtime-scenario, to: deployment-node, cardinality: "0..*"}
  - {from: runtime-scenario, to: stakeholder, cardinality: "0..*", note: "drawn as an actor"}
---

# Relation: steps

The ordered interactions of a runtime scenario. Each entry carries attributes of
its own (both ends, the message), like [[rel-relationships]]. Read by
[[proj-sequence-diagram]]; the inverse, *takes part in*, is listed on the
participants' pages.
