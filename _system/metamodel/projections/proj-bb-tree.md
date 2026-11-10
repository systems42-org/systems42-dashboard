---
type: metamodel
construct: projection
name: bb-tree
aliases: [proj-bb-tree]
reads:
  - {type: building-block, fields: [parent, uses]}
output: tree + diagram
stored: false
implemented: "/arc42/building-blocks"
anchor: arc42
---

# Projection: building-block tree

The levels of the Building Block View from [[rel-parent]]: level 1 under the
system, then each block's children. A block whose parent is empty, a context
page or missing counts as level 1, so nothing drops out of the view.
