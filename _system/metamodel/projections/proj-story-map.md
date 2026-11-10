---
type: metamodel
construct: projection
name: story-map
aliases: [proj-story-map]
reads:
  - {type: functional-requirement, fields: [stereotype, parent, order, priority, release, lane]}
output: table
stored: false
implemented: none
anchor: story-mapping
decision: DR-012-functional-requirement-stereotypes
---

# Projection: story map

Patton's 2-D map over the FR hierarchy: backbone = epics in `order`, ribs = features
and stories by `priority`, swim-lanes = `release`. Fully derivable from the fields
above, so it is never hand-authored ([[story-mapping]]). Not rendered yet; the
dashboard's per-epic breakdown is a one-column cut of it.
