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
naming: "what happens, verb phrase (e.g. Zugangsdaten zurücksetzen)"
fields:
  - {name: steps, kind: structured-list, relation: steps, doc: "ordered interactions {from, to, message, note?}; from/to link a block, external interface, deployment node or stakeholder"}
  - {name: drivers, kind: link-list, relation: drivers, doc: "the use cases, activity models and other requirements this scenario realises"}
  - {name: decisions, kind: link-list, relation: shaped-by, doc: "the decision records behind this flow"}
  - {name: state, kind: enum, values: [outdated, current, planned, target], doc: "outdated = historical, no longer in use; current = in use today; planned = decided, not built yet; target = the intended end state; empty = target"}
  - {name: superseded-by, kind: link, relation: superseded-by, doc: "on a replaced page: its successor"}
anchors: [arc42]
projections: [sequence-diagram]
---

# Type: runtime scenario

arc42 section 6: how the parts work together in one concrete flow — "lost
credentials", "a provider submits a training date". The `steps` are the model;
the sequence diagram is a [[proj-sequence-diagram|projection]]. A step between
two building blocks that have no [[rel-uses]] edge is flagged by
[[rule-runtime-matches-uses]]: the runtime and the static view disagree.
