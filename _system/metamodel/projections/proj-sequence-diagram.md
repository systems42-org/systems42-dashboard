---
type: metamodel
construct: projection
name: sequence-diagram
aliases: [proj-sequence-diagram]
reads:
  - {type: runtime-scenario, fields: [steps]}
  - {type: building-block, fields: [uses, parent]}
output: mermaid
stored: false
implemented: "/page/runtime-scenarios/<RS>"
anchor: arc42
---

# Projection: sequence diagram

One participant per distinct `from` / `to`, in order of first appearance
(stakeholders as actors), one arrow per step. Never stored. Steps between blocks
are checked against [[rel-uses]] ([[rule-runtime-matches-uses]]).
