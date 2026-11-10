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
implemented: "/page/runtime-scenarios/<RS> (sequence diagram + hints)"
anchor: arc42
---

# Projection: sequence diagram

One participant per distinct `from`/`to`, in order of first appearance
(stakeholders as actors), one arrow per step. Never stored. Steps between blocks
are checked against [[rel-uses]] ([[rule-runtime-matches-uses]]). Plain-text ends
keep their text as written (`TCP/IP Gateway`). Nothing is dropped silently: an
entry that is not a `{from, to, message}` mapping, an empty end and an end that
names no page each show as a hint on the scenario page.
