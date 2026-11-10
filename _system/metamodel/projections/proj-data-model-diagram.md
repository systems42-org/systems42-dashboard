---
type: metamodel
construct: projection
name: data-model-diagram
aliases: [proj-data-model-diagram]
reads:
  - {type: data-model, fields: [stereotype, parent, relationships, bounded-context]}
  - {type: glossary-term, fields: [stereotype]}
output: mermaid
stored: false
implemented: "/data-model"
anchor: req42
decision: DR-019-data-model-product-and-sum-types, DR-027-data-model-projected-from-two-carriers
---

# Projection: data-model class diagram

Classes from DM pages, edges from [[rel-relationships]], `<<term>>` stubs from
glossary terms marked `stereotype: entity | value-object`.
