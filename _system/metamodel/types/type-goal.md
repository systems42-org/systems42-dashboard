---
type: metamodel
construct: type
name: goal
aliases: [type-goal, GOAL]
prefix: GOAL
folder: wiki/goals
template: _templates/goal.md
label: Goal
label_de: Ziel
block: R1
lifecycle: content
stereotypes: [vision, objective]
naming: "noun phrase, outcome-oriented"
fields:
  - {name: stereotype, kind: enum, values: [vision, objective], required: true, doc: "vision = the one roof; objective = a PAM sub-goal"}
  - {name: parent, kind: link-list, relation: parent, doc: "objectives point to the vision; the vision has none"}
  - {name: beneficiary, kind: link-list, relation: beneficiary, doc: "who gets the benefit (PAM Advantage)"}
  - {name: metric, kind: scalar, doc: "the single PAM indicator; empty for a vision"}
  - {name: baseline, kind: scalar}
  - {name: target, kind: scalar}
  - {name: horizon, kind: scalar, doc: "empty → PAM, filled → SMART-ready"}
  - {name: short_title, kind: scalar, doc: "label for diagram nodes"}
  - {name: tile_claim, kind: scalar, doc: "vision only: one line for the dashboard tile"}
anchors: [PAM, SMART, req42]
projections: [goal-tree, goal-coverage]
---

# Type: goal

req42 block 01. One type, two stereotypes: exactly one `vision` per wiki, any
number of `objective`s hanging under it via [[rel-parent]]. Framed with [[PAM]]
first; a filled `horizon` promotes the frame to [[SMART]]. "Ziele sind
Anforderungen": goals are the requirements that should stay stable for their period.
