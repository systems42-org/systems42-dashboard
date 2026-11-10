---
type: metamodel
construct: relation
name: superseded-by
aliases: [rel-superseded-by]
field: superseded-by
direction: directed
semantics: revision
inverse: supersedes
inverse_stored: false
reciprocity: none
edges:
  - {from: decision-record, to: decision-record, cardinality: "0..1", note: "set on the old record together with status: deprecated"}
  - {from: building-block, to: building-block, cardinality: "0..1", note: "replaced by its successor; status unchanged, state outdated once gone"}
  - {from: concept, to: concept, cardinality: "0..1", note: "replaced by its successor; status unchanged, state outdated once gone"}
  - {from: runtime-scenario, to: runtime-scenario, cardinality: "0..1", note: "replaced by its successor; status unchanged, state outdated once gone"}
  - {from: deployment-node, to: deployment-node, cardinality: "0..1", note: "replaced by its successor; status unchanged, state outdated once gone"}
---

# Relation: superseded by

Points from a replaced decision to its successor. Unlike [[rel-amends]] it is
stored on the *old* record, which is deprecated at the same time. On architecture
pages it links a page to the one that replaces it; the old page keeps its
`status`, because a correct description of a past or present element stays
correct. Once the old element is gone, its `state` becomes `outdated` (DR-010).
