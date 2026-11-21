---
id: ISS-006
type: issue
title: Should the dashboard run with other container engines than Docker
status: open
created: 2026-11-17
updated: 2026-11-21
sources: ["[[SRC-027-dashboard-distribution-and-metamodel-contract]]", "[[SRC-028-grilling-session-on-dashboard-distribution]]"]
related: ["[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[FR-042-start-a-pinned-release-with-one-command]]"]
tags: [issue]
severity: minor
kind: question
category: requirements
raised-by: "[[STK-012-maintainers]]"
owner: "[[STK-012-maintainers]]"
resolved: null
---

# Should the dashboard run with other container engines than Docker

**What's unresolved.** Whether a compatible container engine such as Podman becomes a supported way to run the dashboard.

**Affects.** [[CON-003-docker-is-the-supported-way-to-run-it]] and the launcher of [[FR-042-start-a-pinned-release-with-one-command]].

**Context / evidence.**
- The source says "we expect a docker (or compatible) container engine" ([[SRC-027-dashboard-distribution-and-metamodel-contract]]).
- Gernot Starke decided on 2026-11-17 to stick to Docker for now, to keep development simple, and to keep other engines as an open issue ([[SRC-028-grilling-session-on-dashboard-distribution]]).
- Tracked in the repository as [issue #24](https://github.com/systems42-org/systems42-dashboard/issues/24).

**Options.**
1. Docker only, as today.
2. Other engines work without a promise, like `./dashboard.sh local`.
3. Podman is tested and supported.

**Resolution.**
