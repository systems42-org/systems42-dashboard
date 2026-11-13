---
id: QR-002
type: quality-requirement
title: Runs alike on Linux and macOS
status: draft
created: 2026-11-13
updated: 2026-11-13
sources: ["[[SRC-019-the-dashboard-as-a-product]]", "[[SRC-020-grilling-session-on-the-dashboard-as-a-product]]"]
related: ["[[FR-029-the-dashboard-as-a-product]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[STK-008-workshop-participants]]", "[[GOAL-008-one-way-into-every-systems42-wiki]]"]
tags: [quality-requirement]
dimensions: [flexible, operable]
priority: should
testable: true
---

# Runs alike on Linux and macOS

**Q42 dimensions.** Flexible, operable.

One release of the dashboard starts the same way and shows the same pages on Linux and on macOS.

**Scenario (Q42 quality scenario).**  <!-- follows [[Q42]], https://quality.arc42.org -->
- **Source.** A [[STK-008-workshop-participants|workshop participant]].
- **Stimulus.** Runs `make dev` in a fresh starter kit on their own laptop.
- **Environment.** A clean Linux or macOS machine with Docker installed, network available for the first start.
- **Response.** The dashboard starts and shows the wiki.
- **Measure.** `make dev` is the only step on both systems. The same release and the same wiki give the same pages on both. Started a second time without network, the dashboard still comes up.

**Applies to.** [[FR-029-the-dashboard-as-a-product]] and its features.
**Tensions.** None known. Windows is out of scope for now ([[CON-003-docker-is-the-supported-way-to-run-it]]).

> [!note] History
> Raised by Gernot Starke on 2026-11-13 ([[SRC-019-the-dashboard-as-a-product]]). Windows dropped for now in question 4, no offline installation in question 6 ([[SRC-020-grilling-session-on-the-dashboard-as-a-product]]).
