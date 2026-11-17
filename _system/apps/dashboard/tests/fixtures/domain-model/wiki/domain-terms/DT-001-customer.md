---
id: DT-001
type: domain-term
title: Customer
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
  - {name: customer_id, type: string, multiplicity: "1", identifier: true}
  - {name: email, type: string, multiplicity: "0..1"}
relationships:
  - {to: "[[DT-002-order]]", label: places, kind: association, multiplicity: "0..*"}
---

# Customer

**Definition.** A person or organization that can place orders.

**In context.** A customer can exist before placing an order.

> [!note] Example data
> This definition belongs to the dashboard's illustrative test model.
