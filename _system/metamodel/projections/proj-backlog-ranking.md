---
type: metamodel
construct: projection
name: backlog-ranking
aliases: [proj-backlog-ranking, backlog]
reads:
  - {type: functional-requirement, fields: [stereotype, priority, release, order, parent]}
output: nested-list
stored: false
implemented: none
anchor: MoSCoW
---

# Projection: backlog ranking

What req42 still calls the Product Backlog: the **ranked, linear** reading of the
hierarchy — by release, then priority, then order. Declared here so that the word
"backlog" has exactly one meaning in this wiki: a view, never a drawer.
