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
  - {from: solution-strategy, to: solution-strategy, cardinality: "0..1", note: "replaced by its successor; status unchanged, state outdated once gone"}
  - {from: runtime-scenario, to: runtime-scenario, cardinality: "0..1", note: "replaced by its successor; status unchanged, state outdated once gone"}
  - {from: deployment-node, to: deployment-node, cardinality: "0..1", note: "replaced by its successor; status unchanged, state outdated once gone"}
  - {from: crosscutting-concept, to: crosscutting-concept, cardinality: "0..1", note: "replaced by its successor; status unchanged, state outdated once gone"}
---

# Relation: superseded by

Points from a replaced decision to its successor. Unlike [[rel-amends]] it is
stored on the *old* record, which is deprecated at the same time. On an
architecture page it links the page to the one that replaces it; the old page
keeps its `status`, since a correct description of a past element stays correct,
and its `state` becomes `outdated` once the element is gone.
