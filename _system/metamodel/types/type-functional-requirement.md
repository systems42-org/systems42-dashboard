---
type: metamodel
construct: type
name: functional-requirement
aliases: [type-functional-requirement, FR]
prefix: FR
folder: wiki/functional-requirements
template: _templates/functional-requirement.md
label: Functional requirement
label_de: Funktionale Anforderung
block: R3
lifecycle: content
stereotypes: [epic, feature, story]
naming: "epic/feature: noun phrase naming an outcome; story: verb + object (convention A)"
fields:
  - {name: stereotype, kind: enum, values: [epic, feature, story], required: true, doc: "level in the Epic → Feature → Story hierarchy"}
  - {name: parent, kind: link-list, relation: parent, doc: "coarser item(s): FR, or a use case for a feature/story; several allowed, so the hierarchy is a graph"}
  - {name: priority, kind: enum, values: [Must, Should, Could, "Won't"], doc: "MoSCoW"}
  - {name: release, kind: scalar, doc: "release/milestone tag, story-map swim-lane; `unscheduled` = not planned"}
  - {name: lane, kind: enum, values: [backbone, platform, display], doc: "story-map lane"}
  - {name: order, kind: int, doc: "narrative order within the lane"}
  - {name: goal, kind: link-list, relation: goal, doc: "goals served; [] = explicit enabler"}
anchors: [user-story-format, acceptance-criteria, INVEST, MoSCoW, story-mapping, req42]
projections: [story-map, backlog-ranking, goal-coverage]
sort_orders:
  - {label: "Priority › release › order", keys: [priority, release, order]}
---

# Type: functional requirement

req42 block 04, **one type with three stereotypes** instead of three types: the
hierarchy is the `parent` relation, and everything else (story map, ranked backlog,
goal coverage) is a [[proj-story-map|projection]] over it. Renamed from "Product
Backlog item" (the 2026 edition of req42).

- Stories carry the story sentence and Gherkin acceptance criteria; epics and
  features carry problem/goal, success metric and scope — same page order for all.
- `goal: []` is a statement, not an omission: the item is an enabler
  ([[proj-goal-coverage]]) — unless its parent is a use case, whose goals it
  then serves.
- A feature or story may refine a use case instead of an epic: `parent:` names
  the use case ([[rel-parent]], DR-011).
- Granularity relative to use cases: see [[altitude]] — **open**.
