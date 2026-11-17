---
id: DT-002
type: domain-term
title: Order
status: draft
created: 2026-11-17
updated: 2026-11-17
sources: []
related: ["[[DT-004-review-policy]]"]
tags: [domain-term, fixture]
aliases: []
bounded-context: Ordering example
agreed: false
stereotype: entity
attributes:
  - {name: order_id, type: string, multiplicity: "1", identifier: true}
relationships:
  - {to: "[[DT-003-order-line]]", label: contains, kind: composition, multiplicity: "1..*"}
---

# Order

**Definition.** A customer's request to purchase one or more products.

**In context.** Each order contains at least one order line. Its lines belong
to that order and share its lifecycle.

> [!note] Example data
> This definition belongs to the dashboard's illustrative test model.
