---
id: BB-005
type: building-block
title: Wiki launcher and Make facade
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-044-building-blocks-of-the-systems42-dashboard]]", "[[SRC-045-grilling-session-on-context-and-building-blocks]]"]
related: ["[[SOL-001-systems42-dashboard]]", "[[STK-010-operators]]"]
tags: [building-block]
parent: "[[CTX-001-systems42-dashboard-context]]"
drivers: ["[[GOAL-008-one-way-into-every-systems42-wiki]]", "[[FR-042-start-a-pinned-release-with-one-command]]", "[[FR-054-a-start-without-a-container-engine]]", "[[FR-063-manage-development-with-make]]", "[[QR-002-runs-alike-on-linux-and-macos]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]"]
decisions: ["[[DR-004-releases-are-container-images-pinned-per-wiki]]", "[[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]"]
uses: ["[[BB-001-python-dashboard]]", "[[BB-002-uv-cli-and-package-wrapper]]", "[[EIF-001-systems42-wiki]]"]
location: "dashboard.sh, Makefile"
state: current
superseded-by:
---

# Wiki launcher and Make facade

> follows [[arc42]] (section 5, black box)

## Purpose / Responsibility

The command-line entry point shipped into every Systems42 wiki: `dashboard.sh` plus the user-facing `Makefile` targets (`dev`, `uv`, `down`, `clean` and `help`). It reads `dashboard_version:` from `_system/wiki.yaml`, starts the pinned release in Docker or with `uv`, opens the browser, prints the LAN workshop address, stops containers, updates the pinned release string and cleans rebuildable artifacts without touching wiki content ([[FR-042-start-a-pinned-release-with-one-command]], [[FR-054-a-start-without-a-container-engine]], [[FR-063-manage-development-with-make]]). Repository-only development and release commands live in `_system/apps/dashboard/dev.sh` and the repository-only `Makefile` targets ([[FR-063-manage-development-with-make]]).

## Interfaces

- **Provides:** `./dashboard.sh [up|down|logs|update|clean|uv]` and `make [help|dev|uv|down|clean]` in every Systems42 wiki root.
- **Needs:** `_system/wiki.yaml` from [[EIF-001-systems42-wiki]], the Docker image of [[BB-001-python-dashboard]] (for `up`) or the release wheel of [[BB-002-uv-cli-and-package-wrapper]] (for `uv`).

## Quality / Performance

Runs alike on Linux and macOS (including macOS Bash 3.2, [[QR-002-runs-alike-on-linux-and-macos]]). Mounts the wiki read-only in Docker and keeps `clean` strictly away from `wiki/`, `raw/`, `docs/` and `sandbox/` ([[CON-002-dashboard-never-writes-to-the-wiki]]).
