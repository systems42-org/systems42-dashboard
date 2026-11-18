---
id: DT-003
type: domain-term
title: Order line
status: draft
created: 2026-11-17
updated: 2026-11-17
sources: []
related: []
tags: [domain-term, fixture]
aliases: []
bounded-context: Ordering example
agreed: false
stereotype: entity
attributes:
  - {name: line_id, type: string, multiplicity: "1", identifier: true}
  - {name: product_code, type: string, multiplicity: "1"}
  - {name: quantity, type: integer, multiplicity: "1"}
relationships: []
---

# Order line

**Definition.** An identified item within an order that specifies a product
and the quantity ordered.

**In context.** A line exists as part of its order.

> [!note] Example data
> This definition belongs to the dashboard's illustrative test model.
