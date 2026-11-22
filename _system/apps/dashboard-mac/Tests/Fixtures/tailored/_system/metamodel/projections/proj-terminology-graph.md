---
type: metamodel
construct: projection
name: terminology-graph
aliases: [proj-terminology-graph]
reads:
  - {type: domain-term, fields: [related, relationships, parent, stereotype, agreed, status, aliases]}
output: graph
stored: false
implemented: "/graph/domain-terms"
anchor: req42
decision: DR-039-one-domain-term-type
---

# Projection: terminology graph

All domain terms are core nodes. Filter the graph by edge kind to inspect links or model structure.
