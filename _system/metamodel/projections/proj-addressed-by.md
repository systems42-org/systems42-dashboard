---
type: metamodel
construct: projection
name: addressed-by
aliases: [proj-addressed-by]
reads:
  - {type: decision-record, fields: [drivers]}
  - {type: building-block, fields: [drivers]}
  - {type: concept, fields: [drivers]}
  - {type: runtime-scenario, fields: [drivers]}
  - {type: deployment-node, fields: [drivers]}
output: list
stored: false
implemented: "requirement detail pages (Addressed by)"
---

# Projection: addressed by

The inverse of [[rel-drivers]] on a goal, use case, functional requirement,
quality requirement, constraint or activity model: which decisions and architecture pages
(blocks, concepts, runtime scenarios, deployment nodes) answer it.
