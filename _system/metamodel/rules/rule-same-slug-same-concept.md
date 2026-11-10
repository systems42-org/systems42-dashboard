---
type: metamodel
construct: rule
name: same-slug-same-concept
aliases: [rule-same-slug-same-concept]
applies_to: {type: any}
check: "pages of different types with the same kebab slug-suffix or identical title link each other in `related`"
confidence: high
action: auto-fix
source: "_system/workflows/relations.md tier 1"
---

# Rule: same slug, same concept

A `GLO-` term and a `DM-` entity with the same slug denote one domain concept;
capture adds the link at write time, the linter mops up history.
