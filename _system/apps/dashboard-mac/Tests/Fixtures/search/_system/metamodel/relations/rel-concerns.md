---
type: metamodel
construct: relation
name: concerns
aliases: [rel-concerns]
field: building-blocks
direction: directed
semantics: assignment
inverse: concerned-by
inverse_stored: false
reciprocity: none
edges:
  - {from: functional-requirement, to: building-block, cardinality: "0..*", note: "set at capture; structures the requirements (FR-005)"}
---

# Relation: concerns

"This requirement concerns that building block." Assignment, not ownership and
not traceability: it structures the requirements by the parts of the system
they apply to, and is set when the requirement is captured. The traceability
statement runs the other way, as the building block's [[rel-drivers|drivers]];
both may connect the same pair, because they say different things
([[FR-005-link-a-requirement-to-a-building-block|FR-005]], DR-038).
