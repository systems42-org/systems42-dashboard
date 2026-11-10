---
type: metamodel
construct: type
name: concept
aliases: [type-concept, CC]
prefix: CC
folder: wiki/concepts
template: _templates/concept.md
label: Crosscutting concept
label_de: Querschnittliches Konzept
block: A5
lifecycle: content
stereotypes: []
naming: "the concept's topic, noun phrase (e.g. Identität und Zugriff)"
fields:
  - {name: category, kind: enum, values: [domain, user-experience, safety-security, patterns, under-the-hood, development, operations], doc: "optional: arc42's concept topics; matched ignoring case, an unknown value is shown under Uncategorised"}
  - {name: applies-to, kind: link-list, relation: applies-to, doc: "the building blocks and deployment nodes that follow this concept; empty = the whole system"}
  - {name: drivers, kind: link-list, relation: drivers, doc: "the requirements this concept answers"}
  - {name: decisions, kind: link-list, relation: shaped-by, doc: "the decision records behind this concept"}
  - {name: state, kind: enum, values: [outdated, current, planned, target], doc: "outdated = historical, no longer in use; current = in use today; planned = decided, not built yet; target = the intended end state; empty = target"}
  - {name: superseded-by, kind: link, relation: superseded-by, doc: "on a replaced page: its successor"}
anchors: [arc42]
projections: [governed-by]
---

# Type: crosscutting concept

arc42 section 8: a practice, pattern, regulation or solution idea that several
building blocks or nodes follow — identity and access, persistence, logging,
backup. The concept is the rule; [[rel-applies-to]] names who follows it, and
its inverse ([[proj-governed-by]]) appears on those pages. arc42's advice holds:
pick only the most-needed topics.
