---
type: metamodel
construct: rule
name: one-term-per-meaning
aliases: [rule-one-term-per-meaning]
applies_to: {type: domain-term}
check: "Review terms that share a title or alias within one bounded context."
confidence: medium
action: ask
source: DR-039-one-domain-term-type
---

# Rule: one term per meaning

Review terms that share a title or alias within one bounded context.
