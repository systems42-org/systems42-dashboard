---
type: metamodel
construct: relation
name: drivers
aliases: [rel-drivers]
field: drivers
direction: directed
semantics: rationale
inverse: addressed-by
inverse_stored: false
reciprocity: none
edges:
  - {from: decision-record, to: goal, cardinality: "0..*"}
  - {from: decision-record, to: use-case, cardinality: "0..*"}
  - {from: decision-record, to: functional-requirement, cardinality: "0..*"}
  - {from: decision-record, to: quality-requirement, cardinality: "0..*"}
  - {from: decision-record, to: constraint, cardinality: "0..*"}
  - {from: building-block, to: goal, cardinality: "0..*"}
  - {from: building-block, to: use-case, cardinality: "0..*"}
  - {from: building-block, to: functional-requirement, cardinality: "0..*"}
  - {from: building-block, to: quality-requirement, cardinality: "0..*"}
  - {from: building-block, to: constraint, cardinality: "0..*"}
  - {from: concept, to: goal, cardinality: "0..*"}
  - {from: concept, to: use-case, cardinality: "0..*"}
  - {from: concept, to: functional-requirement, cardinality: "0..*"}
  - {from: concept, to: quality-requirement, cardinality: "0..*"}
  - {from: concept, to: constraint, cardinality: "0..*"}
  - {from: runtime-scenario, to: goal, cardinality: "0..*"}
  - {from: runtime-scenario, to: use-case, cardinality: "0..*"}
  - {from: runtime-scenario, to: functional-requirement, cardinality: "0..*"}
  - {from: runtime-scenario, to: quality-requirement, cardinality: "0..*"}
  - {from: runtime-scenario, to: constraint, cardinality: "0..*"}
  - {from: deployment-node, to: goal, cardinality: "0..*"}
  - {from: deployment-node, to: use-case, cardinality: "0..*"}
  - {from: deployment-node, to: functional-requirement, cardinality: "0..*"}
  - {from: deployment-node, to: quality-requirement, cardinality: "0..*"}
  - {from: deployment-node, to: constraint, cardinality: "0..*"}
  - {from: runtime-scenario, to: activity-model, cardinality: "0..*", note: "a scenario often realises a process"}
---

# Relation: drivers

"This decision or architecture page rests on that requirement." The bridge from
architecture to requirements, deliberately lightweight: optional, no coverage
rule. The inverse, *addressed by*, is projected onto the requirement pages
([[proj-addressed-by]]). On a decision record it is the linked form of MADR's
"Decision Drivers"; the body section keeps the prose.
