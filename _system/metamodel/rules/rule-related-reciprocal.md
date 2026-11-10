---
type: metamodel
construct: rule
name: related-reciprocal
aliases: [rule-related-reciprocal]
applies_to: {type: any}
check: "if A lists B in `related`, B lists A in `related`"
confidence: high
action: auto-fix
source: "_system/workflows/relations.md tier 2; concept-cluster-audit.py"
---

# Rule: related is reciprocal

Mechanical and safe: the relation is symmetric by declaration
([[rel-related]]), so the missing side is added without asking.
