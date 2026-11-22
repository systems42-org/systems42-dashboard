---
type: metamodel
construct: projection
name: entity-diagram
aliases: [proj-entity-diagram]
reads:
  - {type: domain-term, fields: [stereotype, parent, attributes, relationships, bounded-context]}
output: mermaid
stored: false
implemented: "/entity-diagram"
anchor: req42
decision: DR-019-data-model-product-and-sum-types, DR-039-one-domain-term-type
---

# Projection: entity diagram

Classes are the stereotyped domain terms. Edges come from [[rel-relationships]] and sum-type parents.
