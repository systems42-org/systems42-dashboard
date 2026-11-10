---
type: metamodel
construct: projection
name: whitebox
aliases: [proj-whitebox]
reads:
  - {type: building-block, fields: [parent, uses]}
  - {type: external-interface, fields: []}
output: diagram
stored: false
implemented: "/page/building-blocks/<BB> (white box)"
anchor: arc42
---

# Projection: white box

A block's inner structure: its children as boxes, their [[rel-uses]] dependencies
as arrows, external interfaces they use as neighbour boxes, all states in one
picture with the marks of [[proj-deployment-diagram]]. Never stored.
