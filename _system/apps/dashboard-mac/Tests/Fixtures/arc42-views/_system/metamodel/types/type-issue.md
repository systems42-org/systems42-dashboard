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
  - {name: category, kind: enum, values: [requirements, architecture, commons, content, orga, method], doc: "which part of the work it touches; optional, at most one"}
  - {name: raised-by, kind: link, relation: raised-by, doc: "`agent` or a stakeholder link"}
  - {name: owner, kind: link, relation: owner, doc: "the stakeholder the question is addressed to; a stakeholder link only, empty means not yet clear"}
  - {name: resolved, kind: date, doc: "when status became resolved / wontfix"}
anchors: [req42]
projections: []
---

# Type: issue

The one **meta** type (DR-003): it cross-cuts every other type through
[[rel-related]]. `kind: risk` is how req42 block 12 is captured. An Issue is where
a question goes **after** the human was asked and did not answer (grilling first).

`category` says which part of the work an issue touches, `kind` says what sort of
problem it is. The two are independent: a risk is a kind, not a category. The
values mix two things on purpose: `requirements`, `architecture` and `commons` are
the three areas (the `area` keys of the metamodel), while `content` (housekeeping
of the wiki itself), `orga` (authority, budget, schedule) and `method` (the
Systems42 method: metamodel, templates, workflows) name a kind of work. The field
is optional; leave it empty when an issue spans several areas.

`owner` names the stakeholder the question is addressed to: the one whose answer
resolves it. Most stakeholders are groups, so this is not an assignment to a
person, and there is no due date: the wiki is not a project management tool.
Unlike `raised-by`, it takes no literal and no free name, only a `[[STK-...]]` link.
