---
type: metamodel
construct: type
name: runtime-scenario
aliases: [type-runtime-scenario, RS]
prefix: RS
folder: wiki/runtime-scenarios
template: _templates/runtime-scenario.md
label: Runtime scenario
label_de: Laufzeitszenario
block: A4
lifecycle: content
stereotypes: []
naming: "what happens, as a verb phrase"
fields:
  - {name: steps, kind: structured-list, relation: steps, doc: "ordered interactions {from, to, message, note?}; from/to link a building block, external interface, deployment node or stakeholder"}
  - {name: realizes, kind: link-list, relation: realizes, doc: "the functional requirement or activity model this scenario carries out"}
  - {name: decisions, kind: link-list, relation: shaped-by, doc: "the decision records behind this flow"}
  - {name: state, kind: enum, values: [outdated, current, planned, target], doc: "outdated = historical, no longer in use; current = in use today; planned = decided, not built yet; target = the intended end state; empty = target"}
  - {name: superseded-by, kind: link, relation: superseded-by, doc: "on a replaced page: its successor"}
anchors: [arc42]
projections: [sequence-diagram]
---

# Type: runtime scenario

arc42 section 6: how the parts interact in one architecturally relevant
scenario — an important use case, a critical external interface, start-up,
an error case. A representative selection, not completeness. The `steps` are
the model; the sequence diagram is a [[proj-sequence-diagram|projection]],
never drawn. The requirements view of the same flow is the
[[type-activity-model]] or the FR; [[rel-realizes]] links it instead of
repeating it. A step between blocks without a [[rel-uses]] edge is flagged by
[[rule-runtime-matches-uses]].
