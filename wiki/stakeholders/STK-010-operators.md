---
id: STK-010
type: stakeholder
title: Operators
status: draft
created: 2026-11-10
updated: 2026-11-20
sources: ["[[SRC-001-stakeholders-of-the-systems42-dashboard]]", "[[SRC-002-grilling-session-on-stakeholders]]", "[[SRC-036-grilling-session-on-running-without-a-container-engine]]"]
related: ["[[STK-023-keyholder]]", "[[STK-012-maintainers]]", "[[ISS-001-who-holds-the-keys-in-parallel-work]]", "[[FR-054-a-start-without-a-container-engine]]", "[[FR-055-an-installable-dashboard-app]]"]
tags: ["stakeholder"]
aliases: ["People who run the dashboard", "People who set up a project wiki"]
role: Person who sets up a project wiki and runs its dashboard
influence: low
interest: medium
provides: ["start and stop"]
receives: ["the running dashboard", "its address and QR code"]
nature: person
context_role: Operator
---

# Operators

**Snapshot.** Operators set up a project wiki and give it its name, tagline and About page. They start, stop and clean up the dashboard (`dashboard.sh`, `make dev`, `make clean`). Whoever starts it is usually the [[STK-023-keyholder|Keyholder]].

**Goals.**
- Start and stop the dashboard reliably, with or without Docker.

**Concerns / pains.**
- On a workshop laptop, Docker may not start.
- Inside a virtual machine, no container engine runs ([[SRC-036-grilling-session-on-running-without-a-container-engine]]).
