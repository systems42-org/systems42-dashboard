---
type: metamodel
construct: type
name: issue
aliases: [type-issue, ISS]
prefix: ISS
folder: wiki/issues
template: _templates/issue.md
label: Issue
label_de: Offener Punkt
block: C6
lifecycle: issue
stereotypes: []
naming: "the open question in one line"
fields:
  - {name: severity, kind: enum, values: [blocker, major, minor]}
  - {name: kind, kind: enum, values: [question, contradiction, gap, ambiguity, risk]}
  - {name: raised-by, kind: link, relation: raised-by, doc: "`agent` or a stakeholder link"}
  - {name: resolved, kind: date, doc: "when status became resolved / wontfix"}
anchors: [req42]
projections: []
---

# Type: issue

The one **meta** type (DR-003): it cross-cuts every other type through
[[rel-related]]. `kind: risk` is how req42 block 12 is captured. An Issue is where
a question goes **after** the human was asked and did not answer (grilling first).
