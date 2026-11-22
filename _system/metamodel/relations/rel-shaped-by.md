---
type: metamodel
construct: relation
name: shaped-by
aliases: [rel-shaped-by]
field: decisions
direction: directed
semantics: rationale
inverse: shapes
inverse_stored: false
reciprocity: none
edges:
  - {from: building-block, to: decision-record, cardinality: "0..*"}
  - {from: solution-strategy, to: decision-record, cardinality: "0..*"}
  - {from: crosscutting-concept, to: decision-record, cardinality: "0..*"}
  - {from: runtime-scenario, to: decision-record, cardinality: "0..*"}
  - {from: deployment-node, to: decision-record, cardinality: "0..*"}
---

# Relation: shaped by

The decision records that shaped an architecture page (field `decisions`). Together
with [[rel-drivers]] it answers "why is this block like this?".
