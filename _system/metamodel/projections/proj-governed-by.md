---
type: metamodel
construct: projection
name: governed-by
aliases: [proj-governed-by]
reads:
  - {type: concept, fields: [applies-to]}
output: list
stored: false
implemented: "block and node detail pages (Governed by)"
---

# Projection: governed by

The inverse of [[rel-applies-to]]: which crosscutting concepts a block or node
follows. Concepts with an empty `applies-to` govern the whole system and are
listed on the concepts view, not on every page.
