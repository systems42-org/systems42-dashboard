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
  - {name: category, kind: enum, values: [requirements, architecture, commons, content, orga, systems42], doc: "which part of the work it touches; exactly one"}
  - {name: raised-by, kind: link, relation: raised-by, doc: "`agent` or a stakeholder link"}
  - {name: owner, kind: link, relation: owner, doc: "who is expected to answer: a name or a stakeholder link; empty means nobody yet"}
  - {name: resolved, kind: date, doc: "when status became resolved / wontfix"}
anchors: [req42]
projections: []
---

# Type: issue

The one **meta** type (DR-003): it cross-cuts every other type through
[[rel-related]]. `kind: risk` is how req42 block 12 is captured. An Issue is where
a question goes **after** the human was asked and did not answer (grilling first).

`category` says which part of the work an issue touches, `kind` says what sort of
problem it is. They are independent: a risk is a kind, not a category. The first
three categories are the three areas. `content` is housekeeping of the wiki
itself, `orga` is who decides, budget and schedule, `systems42` is the method
itself (FR-026).
