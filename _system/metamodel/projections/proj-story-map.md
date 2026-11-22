---
type: metamodel
construct: projection
name: story-map
aliases: [proj-story-map]
reads:
  - {type: functional-requirement, fields: [notation, level, parent, order, priority, release, lane]}
output: table
stored: false
implemented: none
anchor: story-mapping
decision: DR-038-functional-requirement-notations-and-levels
---

# Projection: story map

Patton's 2-D map over Agile FRs: backbone = epics in `order`, ribs = features
and stories by `priority`, swim-lanes = `release`. Fully derivable from the fields
above, so it is never hand-authored ([[story-mapping]]). Other notations remain
in the unified FR list and are not forced into this projection. One exception: a
sea- or fish-level use case that Agile features or stories name as `parent:`
appears as a root beside the epics, with those children under it (DR-038
amendment).
