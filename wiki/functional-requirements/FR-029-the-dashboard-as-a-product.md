---
id: FR-029
type: functional-requirement
title: The dashboard as a product
status: draft
created: 2026-11-13
updated: 2026-11-13
sources: ["[[SRC-019-the-dashboard-as-a-product]]", "[[SRC-020-grilling-session-on-the-dashboard-as-a-product]]"]
related: ["[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[QR-002-runs-alike-on-linux-and-macos]]", "[[DR-004-releases-are-container-images-pinned-per-wiki]]", "[[CON-001-proof-of-concept-not-production-ready]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[STK-012-maintainers]]"]
tags: ["functional-requirement", "product"]
stereotype: epic
parent: []
priority: Should
release: unscheduled
lane: backbone
order: 29
goal: ["[[GOAL-002-show-what-systems42-can-do]]", "[[GOAL-008-one-way-into-every-systems42-wiki]]"]
---

# The dashboard as a product

## Epic: Summary

As a [[STK-011-people-who-set-up-a-project-wiki|person who sets up a project wiki]] I want **to use a released dashboard as it is and make it look like my project by configuration**, so that **my wiki gets every fix and feature without a private copy of the code**.

**PROBLEM / GOAL**

The dashboard is a product of its own, with numbered releases. Any Systems42 wiki uses a released version as it is. What makes it look like one project is configuration in the wiki.

These rules hold for every feature below:

- **One home for the code.** The dashboard code lives only in the dashboard's own repository. Other wikis (isaqb-atrium, the starter kit, project wikis) hold no copy ([[DR-004-releases-are-container-images-pinned-per-wiki]]).
- **Configuration in one file.** A wiki sets its dashboard in `_system/wiki.yaml`: `dashboard_version:`, `brand:` and `intro:`, next to the name and tagline.
- **Docker.** Docker is the supported way to run it ([[CON-003-docker-is-the-supported-way-to-run-it]]). It runs alike on Linux and macOS ([[QR-002-runs-alike-on-linux-and-macos]]).
- **Start and stop.** `make dev` starts it, `make down` stops it, `make clean` removes what can be rebuilt. The Makefile calls `dashboard.sh`.
- **Read only and offline.** The dashboard reads the configuration and the brand folder, never writes them ([[CON-002-dashboard-never-writes-to-the-wiki]]). After the first start it runs without network.

**Success metric(s).** A fresh starter kit on a clean Linux or macOS machine with Docker shows its dashboard after `make dev`, with no other step.

**Scope.** in: releases, branding by configuration, example brands, a runnable dashboard in the starter kit · out: Windows (for now), running without Docker as a supported way, hosting for many users ([[CON-001-proof-of-concept-not-production-ready]]).

## Hierarchy

- **Parent:** none (epic).
- **Children:** projected from the `parent:` backlinks: [[FR-030-numbered-releases]], [[FR-031-branding-is-configuration]], [[FR-032-example-brands-to-try]], [[FR-033-runnable-dashboard-in-the-starter-kit]].

> [!note] Open points
> None. Gernot Starke agreed Should for the epic and FR-030, FR-032, FR-033, and Must for FR-031, on 2026-11-13.

## History

> Raised by Gernot Starke on 2026-11-13 ([[SRC-019-the-dashboard-as-a-product]]). Shaped in seven questions ([[SRC-020-grilling-session-on-the-dashboard-as-a-product]]): GOAL-002 and a new goal, one epic with four features, three keys in `wiki.yaml`, Windows ignored for now, `./dashboard.sh local` as an unsupported fallback, no offline installation, and container images per release (DR-004).
