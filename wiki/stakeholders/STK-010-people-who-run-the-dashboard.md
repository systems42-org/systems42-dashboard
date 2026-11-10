---
id: STK-010
type: stakeholder
title: People who run the dashboard
status: draft
created: 2026-11-10
updated: 2026-11-10
sources: ["[[SRC-001-stakeholders-of-the-systems42-dashboard]]", "[[SRC-002-grilling-session-on-stakeholders]]"]
related: ["[[STK-007-workshop-facilitators]]", "[[STK-023-keyholder]]", "[[ISS-001-who-holds-the-keys-in-parallel-work]]"]
tags: ["stakeholder"]
aliases: ["Operator"]
role: "Person who starts, stops and cleans up the dashboard"
influence: low
interest: medium
provides: ["start and stop"]
receives: ["the running dashboard", "its address and QR code"]
nature: person
context_role: Operator
---

# People who run the dashboard

**Snapshot.** Someone has to start the dashboard, stop it and clean up after it (`dashboard.sh`, `make dev`, `make clean`). Sometimes this is the workshop facilitator ([[STK-007-workshop-facilitators]]). Whoever starts the app is the Keyholder ([[STK-023-keyholder]]).

**Goals.**
- Start and stop the dashboard reliably, with or without Docker.

**Concerns / pains.**
- On a workshop laptop, Docker may not start.

**Interactions.** None recorded yet.
