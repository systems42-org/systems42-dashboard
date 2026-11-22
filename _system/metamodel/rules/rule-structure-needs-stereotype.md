---
type: metamodel
construct: rule
name: structure-needs-stereotype
aliases: [rule-structure-needs-stereotype]
applies_to: {type: domain-term}
check: "Terms with attributes, relationships or a parent carry a stereotype. Relationship targets are stereotyped. Only entities have a source of truth or identifier attributes."
confidence: high
action: ask
source: DR-039-one-domain-term-type
---

# Rule: structure needs stereotype

Terms with attributes, relationships or a parent carry a stereotype. Relationship targets are stereotyped. Only entities have a source of truth or identifier attributes.
