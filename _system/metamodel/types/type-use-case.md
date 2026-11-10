---
type: metamodel
construct: type
name: use-case
aliases: [type-use-case, UC]
prefix: UC
folder: wiki/use-cases
template: _templates/use-case.md
label: Use case
label_de: Anwendungsfall
block: R3
lifecycle: content
stereotypes: []
naming: "verb + object, the actor's goal (convention A)"
fields:
  - {name: primary-actor, kind: link, relation: primary-actor}
  - {name: level, kind: enum, values: [summary, user-goal, subfunction], doc: "Cockburn altitude of the goal"}
  - {name: priority, kind: enum, values: [must, should, could, wont], doc: "MoSCoW"}
  - {name: goal, kind: link-list, relation: goal, doc: "goals served (0..*)"}
anchors: [MoSCoW, req42]
projections: [goal-coverage]
---

# Type: use case

req42 block 04 (Functional Requirements, DR-011): an actor's goal with preconditions, main flow, alternates and
postconditions. A use case *is* a functional requirement, a second form beside
the FR type; `goal:` names the goals it serves, like an epic's. Use cases and functional requirements are **parallel structures**:
a use case may exist without an epic, an epic may have only features and stories,
and both vocabularies may be used side by side. How their granularities compare is
**deliberately undecided** — see [[altitude]]. A use case can be broken down
like an epic: features and stories name it in `parent:` ([[rel-parent]]), and
its "Realized by" list is projected from those backlinks, never stored. A use
case has no parent itself. Supporting actors are prose wikilinks, not declared
relations.
