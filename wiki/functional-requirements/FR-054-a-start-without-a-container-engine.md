---
id: FR-054
type: functional-requirement
title: A start without a container engine
status: draft
created: 2026-11-20
updated: 2026-11-20
sources: ["[[SRC-036-grilling-session-on-running-without-a-container-engine]]"]
related: ["[[FR-042-start-a-pinned-release-with-one-command]]", "[[FR-050-stop-the-dashboard-when-nobody-is-watching]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[QR-002-runs-alike-on-linux-and-macos]]", "[[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]", "[[FR-055-an-installable-dashboard-app]]"]
tags: ["functional-requirement", "product"]
stereotype: feature
parent: ["[[FR-029-the-dashboard-as-a-product]]"]
priority: Should
release: unscheduled
lane: backbone
order: 54
goal: ["[[GOAL-008-one-way-into-every-systems42-wiki]]"]
---

# A start without a container engine

## Story

As a [[STK-010-operators|person who runs the dashboard]] inside a virtual machine I want **to start the release my wiki names without Docker**, so that **I get the same dashboard where no container engine runs**.

**PROBLEM / GOAL**

- **Why.** Some people run their Systems42 wiki inside a virtual machine. Neither Docker nor Podman starts there.
- **One command.** `./dashboard.sh uv` (or `make uv`) starts the dashboard with uv. uv is the one thing to install. It fetches Python and the release.
- **The same release.** It starts the release that `dashboard_version:` names, as [[FR-042-start-a-pinned-release-with-one-command]] does. Every release carries a Python package for it, next to the container image ([[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]).
- **The same dashboard.** It runs the code and the server of the container image, at the same address. It still writes nothing to the wiki ([[CON-002-dashboard-never-writes-to-the-wiki]]).
- **In the foreground.** Ctrl+C stops it, and so does closing the last page ([[FR-050-stop-the-dashboard-when-nobody-is-watching]]).

**Success metric(s).** In a Systems42 derivative on a machine with uv and without Docker, `./dashboard.sh uv` shows the dashboard in the release the wiki names. Started a second time without network, it still comes up.

**Scope.** in: the launcher command, the package per release · out: Windows, installing uv, an app that needs no terminal ([[FR-055-an-installable-dashboard-app]]).

## Hierarchy

- **Parent:** [[FR-029-the-dashboard-as-a-product]]
- **Children:** none.

> [!note] Open points
> - Releases up to 0.12.0 carry no package. The launcher says so and names `./dashboard.sh update`.

## History

> Asked for by Gernot Starke on 2026-11-20. He chose the package on the GitHub release over a git tag and over PyPI ([[SRC-036-grilling-session-on-running-without-a-container-engine]]). The priority is Claude's proposal.
