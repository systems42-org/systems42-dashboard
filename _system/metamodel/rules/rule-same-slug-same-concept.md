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

A domain term and the building block that implements it can share a name.
Capture links the two views of that concept.
