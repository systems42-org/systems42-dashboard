---
type: metamodel
construct: type
name: crosscutting-concept
aliases: [type-crosscutting-concept, CC]
prefix: CC
folder: wiki/crosscutting-concepts
template: _templates/crosscutting-concept.md
label: Crosscutting concept
label_de: Querschnittliches Konzept
block: A5
lifecycle: content
stereotypes: []
naming: "the topic, e.g. Logging, Error handling"
fields:
  - {name: category, kind: enum, values: [domain, user-experience, safety-security, patterns, under-the-hood, development, operations], doc: "optional: arc42's concept topics"}
  - {name: applies-to, kind: link-list, relation: applies-to, doc: "the building blocks and deployment nodes that follow it; empty = the whole system"}
  - {name: drivers, kind: link-list, relation: drivers, doc: "the requirements this concept answers"}
  - {name: decisions, kind: link-list, relation: shaped-by, doc: "the decision records that chose it"}
  - {name: state, kind: enum, values: [outdated, current, planned, target], doc: "outdated = historical, no longer in use; current = in use today; planned = decided, not built yet; target = the intended end state; empty = target"}
  - {name: superseded-by, kind: link, relation: superseded-by, doc: "on a replaced page: its successor"}
anchors: [arc42]
projections: [governed-by]
---

# Type: crosscutting concept

arc42 section 8: a practice, pattern, rule or solution idea that several
building blocks or nodes follow — the basis of conceptual integrity. Always
called *crosscutting concept*, never *concept*: a glossary concept is a
[[type-domain-term]]. A choice among alternatives is a [[type-decision-record]],
a limit is a [[type-constraint]]; this page holds the practice and links them.
Pick only the topics the system needs.
