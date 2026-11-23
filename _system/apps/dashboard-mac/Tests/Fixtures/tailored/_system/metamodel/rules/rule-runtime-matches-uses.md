---
type: metamodel
construct: rule
name: runtime-matches-uses
aliases: [rule-runtime-matches-uses]
applies_to: {type: runtime-scenario}
check: "for each step whose from and to are both building blocks, from (or a parent: ancestor of it) lists to (or an ancestor of to) in uses:"
confidence: medium
action: ask
source: "arc42 runtime and building-block view consistency"
---

# Rule: runtime steps match static dependencies

Advisory: capture and inspect ask the human whether the step or the `uses:` edge
is wrong. Never edits either.
