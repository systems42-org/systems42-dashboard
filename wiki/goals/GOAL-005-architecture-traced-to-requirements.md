---
id: GOAL-005
type: goal
title: Architecture and decisions traced to requirements
status: draft
created: 2026-11-10
updated: 2026-11-10
sources: ["[[SRC-004-goals-of-the-systems42-dashboard]]"]
related: []
tags: ["goal"]
stereotype: objective
parent: ["[[GOAL-001-trusted-answers]]"]
beneficiary: ["[[STK-009-software-architects]]", "[[STK-004-development-teams]]", "[[STK-017-operations-staff]]"]
metric: "Share of `drivers:` links shown on both linked pages."
baseline:
target: "100 %"
horizon:
short_title: Traced architecture
tile_claim:
---

# Architecture and decisions traced to requirements

## Objective

> follows [[PAM]]

*From the vision: "how the system is built to meet it, and what has been decided."*

- **Purpose.** From any requirement the reader reaches the building blocks and decisions that answer it, and from any block or decision the requirements behind it. They see which parts hold today.
- **Advantage.** Development teams know the limits and the reasons before they change something. Architects stop explaining the same decision again. Nobody builds on a decision that was replaced.
- **Metric.** Share of `drivers:` links shown on both linked pages. Proposed target: 100 %.

> [!note]
> The target is a proposal. Nobody has agreed it yet. No baseline has been measured.

**What the metric means.** A building block or decision names the requirements it answers in its `drivers:` field. The dashboard shows that link on both pages, on the block or decision and on the requirement. The metric is the share of these links shown on both sides. An automated test can check it on every change.

**Parent.** [[GOAL-001-trusted-answers]].

## Impact

- **Addressed stakeholders:** see `beneficiary:`.
- **Served by:** projected from the FR backlinks.
