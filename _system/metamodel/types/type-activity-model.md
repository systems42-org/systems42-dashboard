---
type: metamodel
construct: type
name: activity-model
aliases: [type-activity-model, ACT]
prefix: ACT
folder: wiki/activity-models
template: _templates/activity-model.md
label: Activity model
label_de: Aktivitätsmodell
block: R4
lifecycle: content
stereotypes: []
naming: "process name"
fields:
  - {name: actors, kind: link-list, relation: actors}
  - {name: trigger, kind: scalar, doc: "what starts the process"}
anchors: [req42]
projections: []
---

# Type: activity model

req42 block 05: an actor-driven process, trigger → steps → outcome. Granularity
relative to use cases and epics is part of the open [[altitude]] question.
