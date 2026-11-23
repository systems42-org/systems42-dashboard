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
stereotypes: []
naming: "Defined by notation; Agile defaults to epic/feature nouns and story verbs; Cockburn use cases express actor goals"
fields:
  - {name: notation, kind: scalar, required: true, doc: "writing form and level vocabulary: an explicit choice, else default_notation in wiki.yaml, else agile"}
  - {name: level, kind: scalar, required: true, doc: "one of the selected notation's levels; independent of graph depth"}
  - {name: parent, kind: link-list, relation: parent, doc: "coarser item(s); several allowed, so the hierarchy is a graph"}
  - {name: building-blocks, kind: link-list, relation: concerns, doc: "building blocks this requirement concerns; assignment, set at capture (FR-005)"}
  - {name: priority, kind: enum, values: [Must, Should, Could, "Won't"], doc: "MoSCoW"}
  - {name: release, kind: scalar, doc: "release/milestone tag; `unscheduled` = not planned"}
  - {name: lane, kind: enum, values: [backbone, platform, display], doc: "story-map lane"}
  - {name: order, kind: int, doc: "narrative order within the lane"}
  - {name: goal, kind: link-list, relation: goal, doc: "goals served; [] = explicit enabler"}
  - {name: delivery, kind: enum, values: [partial, implemented, outdated, removed], doc: "optional implementation state on directly implementable levels; absent means no delivery record"}
  - {name: delivery-checked, kind: timestamp, doc: "optional ISO 8601 check timestamp; Git derives the implementation baseline from the commit that changes either delivery field"}
anchors: [MoSCoW, req42]
projections: [story-map, backlog-ranking, goal-coverage]
---

# Type: functional requirement

req42 block 04, **one functional-requirement type** with notation-specific
`level:` values. The hierarchy is the `parent` relation, independent of level;
the story map, ranked backlog and goal coverage are projections. Notation and
level vocabularies are defined by the selected notation. Renamed from "Product
Backlog item" in the 2026 edition of req42.

- Each notation defines its writing form, levels, optional fields, anchors and
  body sections; the Agile default carries the existing epic/feature/story form.
- Direct delivery fields are optional and may appear only on levels declared
  implementable by their notation. Git history derives the latest baseline from
  a committed `implemented` or `partial` record; an `outdated` state preserves
  that prior baseline.
- `goal: []` is a statement, not an omission: the item is an enabler
  ([[proj-goal-coverage]]).
- `parent:` may cross notations in one case: an Agile feature or story may
  refine a use case at level `sea` or `fish` (a slice of its flows). An epic
  never names a use case, and a kite-level use case takes no Agile children.
  The use case's page shows what realizes it; it is projected, never stored
  (DR-038 amendment).
