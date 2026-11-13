---
id: DR-004
type: decision-record
title: Releases are container images, pinned per wiki
status: accepted
created: 2026-11-13
updated: 2026-11-13
sources: ["[[SRC-020-grilling-session-on-the-dashboard-as-a-product]]"]
related: ["[[FR-029-the-dashboard-as-a-product]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[STK-012-maintainers]]"]
tags: [decision-record]
aliases: []
kind: architecture
decided: 2026-11-13
decision-makers: [Gernot Starke]
consulted: [Claude]
informed: []
drivers: ["[[FR-030-numbered-releases]]", "[[GOAL-008-one-way-into-every-systems42-wiki]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]"]
amends: []
superseded-by: []
---

# Releases are container images, pinned per wiki

> follows [[MADR]]

## Context and Problem Statement

Several wikis use the dashboard: this one, isaqb-atrium, the starter kit and project wikis. Until now each held its own copy of the code, and the copies drifted apart. How does a release reach a wiki?

## Considered Options

1. A container image per release, named by the wiki.
2. A git submodule or subtree.
3. A copy of the code in each wiki, synced by script.
4. A Python package.

## Decision Outcome

Chosen option: **1**. Every git tag of the dashboard repository publishes an image, `ghcr.io/systems42-org/dashboard:<version>`. A wiki names its release in `_system/wiki.yaml` as `dashboard_version:`, and `dashboard.sh` starts that image. No wiki holds dashboard code.

It needs only Docker ([[CON-003-docker-is-the-supported-way-to-run-it]]), behaves the same everywhere, and leaves no code to drift. A submodule or a copy keeps the drift, a package needs Python on every machine.

### Consequences

- Good: one source for the code, and updates only when a wiki asks.
- Bad: the first start needs network to pull the image.
- Bad: the new-project sync must stop copying the dashboard code into wikis.
