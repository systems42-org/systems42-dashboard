---
type: metamodel
construct: projection
name: addressed-by
aliases: [proj-addressed-by]
reads:
  - {type: decision-record, fields: [drivers]}
  - {type: building-block, fields: [drivers]}
  - {type: solution-strategy, fields: [drivers]}
  - {type: deployment-node, fields: [drivers]}
  - {type: crosscutting-concept, fields: [drivers]}
output: list
stored: false
implemented: "requirement detail pages (Addressed by)"
---

# Projection: addressed by

The inverse of [[rel-drivers]] on a goal, use case, functional requirement,
quality requirement or constraint: which decisions, building blocks, solution strategies, deployment nodes and
crosscutting concepts answer it.
