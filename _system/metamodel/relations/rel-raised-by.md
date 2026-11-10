---
type: metamodel
construct: relation
name: raised-by
aliases: [rel-raised-by]
field: raised-by
direction: directed
semantics: origin
inverse: raised
inverse_stored: false
reciprocity: none
edges:
  - {from: issue, to: stakeholder, cardinality: "0..1", note: "or the literal `agent` — the one field that is link-or-literal"}
---

# Relation: raised by

Who put the question on the table. The literal `agent` is allowed because most
Issues come out of capture, not from a stakeholder.
