---
type: metamodel
construct: type
name: solution-strategy
aliases: [type-solution-strategy, SOL]
prefix: SOL
folder: wiki/solution-strategy
template: _templates/solution-strategy.md
label: Solution strategy
label_de: Lösungsstrategie
block: A1
lifecycle: content
stereotypes: []
naming: "the system's name"
fields:
  - {name: drivers, kind: link-list, relation: drivers, doc: "the quality goals, goals and constraints the strategy answers"}
  - {name: decisions, kind: link-list, relation: shaped-by, doc: "the decision records it summarises — linked, never restated"}
  - {name: state, kind: enum, values: [outdated, current, planned, target], doc: "outdated = historical, no longer in use; current = in use today; planned = decided, not built yet; target = the intended end state; empty = target"}
  - {name: superseded-by, kind: link, relation: superseded-by, doc: "on a replaced page: its successor"}
anchors: [arc42]
projections: []
---

# Type: solution strategy

arc42 section 4: a short, motivated summary of the fundamental decisions —
technology, top-level decomposition, how key quality goals are met, relevant
organisational choices. One page per `state`: a current and a target strategy
are two pages, the old one `superseded-by:` the new. The decisions live in
[[type-decision-record]] pages; this page links them in [[rel-shaped-by]] and
explains why they fit together, it never restates them.
