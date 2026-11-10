---
id: DR-NNN
type: decision-record
title: <The decision, as an active statement>
status: draft         # draft | review | accepted | deprecated
created: {{date}}
updated: {{date}}
sources: []
related: []           # [[FR-...]], [[QR-...]], [[CON-...]], [[GLO-...]], other [[DR-...]]
tags: [decision-record]
aliases: []           # former IDs, e.g. ADR-0012
kind: undefined       # architecture | business | undefined (only when genuinely unclear)
decided: {{date}}     # when the decision was taken (not when the page was written)
decision-makers: []   # optional: names of the people who decided ([[MADR]])
consulted: []         # optional: names of the people whose advice was sought
informed: []          # optional: names of the people who were told
drivers: []           # [[GOAL-...]], [[UC-...]], [[FR-...]], [[QR-...]], [[CON-...]] this decision rests on
amends: []            # [[DR-...]] whose points this record changes
superseded-by: []     # [[DR-...]] successor; set together with status: deprecated
---

# {{title}}

> follows [[MADR]]

<!-- A decision record passes all three tests in [[MADR]]: cross-cutting,
     expensive to reverse, a real choice among named alternatives. A standing
     rule or wanted capability is a requirement (FR, QR, CON) instead; a field
     addition, rename or naming convention is a CHANGELOG.md entry. When unsure,
     ask the human. -->

## Context and Problem Statement

<The forces at play and the question to decide.>

## Decision Drivers

<Optional. The forces that weigh most.>

## Considered Options

1. <Option A>
2. <Option B>

## Decision Outcome

Chosen option: **<Option>**, because <reason>.

### Consequences

- Good: <what becomes easier>
- Bad: <what becomes harder>

### Confirmation

<Optional. How compliance with the decision is checked.>

## Pros and Cons of the Options

<Optional. Per option, the arguments for and against.>

## More Information

<Optional. Links, follow-ups. Later changes go in dated "Amendment (YYYY-MM-DD)" sections here.>
