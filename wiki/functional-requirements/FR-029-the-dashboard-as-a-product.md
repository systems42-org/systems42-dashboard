---
id: FR-029
type: functional-requirement
title: The dashboard as a product
status: draft
created: 2026-11-13
updated: 2026-11-20
sources: ["[[SRC-019-the-dashboard-as-a-product]]", "[[SRC-020-grilling-session-on-the-dashboard-as-a-product]]", "[[SRC-027-dashboard-distribution-and-metamodel-contract]]", "[[SRC-028-grilling-session-on-dashboard-distribution]]", "[[SRC-036-grilling-session-on-running-without-a-container-engine]]"]
related: ["[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[QR-002-runs-alike-on-linux-and-macos]]", "[[DR-004-releases-are-container-images-pinned-per-wiki]]", "[[CON-001-proof-of-concept-not-production-ready]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[STK-012-maintainers]]", "[[DR-005-the-dashboard-lives-in-its-own-repository]]", "[[CON-005-the-dashboard-works-on-systems42-derivatives-only]]", "[[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]"]
tags: ["functional-requirement", "product"]
notation: agile
level: epic
parent: []
priority: Should
release: unscheduled
lane: backbone
order: 29
goal: ["[[GOAL-002-show-what-systems42-can-do]]", "[[GOAL-008-one-way-into-every-systems42-wiki]]"]
---

# The dashboard as a product

## Epic: Summary

As a [[STK-010-operators|person who sets up a project wiki]] I want **to use a released dashboard as it is and make it look like my project by configuration**, so that **my wiki gets every fix and feature without a private copy of the code**.

**PROBLEM / GOAL**

The dashboard is a product of its own, with numbered releases. Any Systems42 wiki uses a released version as it is. What makes it look like one project is configuration in the wiki.

These rules hold for every feature below:

- **One home for the code.** The dashboard code lives only in the dashboard's own repository ([[DR-005-the-dashboard-lives-in-its-own-repository]]). Other wikis (isaqb-atrium, the starter kit, project wikis) hold no dashboard code except the launcher, currently `dashboard.sh`, which a Makefile may call ([[DR-004-releases-are-container-images-pinned-per-wiki]], [[FR-042-start-a-pinned-release-with-one-command]]).
- **Configuration in one file.** A wiki sets its dashboard in `_system/wiki.yaml`: `dashboard_version:`, `brand:` and `intro:`, next to the name and tagline.
- **Docker or uv.** Docker is the supported way to run it, and uv where no container engine runs ([[CON-003-docker-is-the-supported-way-to-run-it]], [[FR-054-a-start-without-a-container-engine]]). It runs alike on Linux and macOS ([[QR-002-runs-alike-on-linux-and-macos]]).
- **Start and stop.** `make dev` starts it, `make down` stops it, `make clean` removes what can be rebuilt. The Makefile calls `dashboard.sh`.
- **Read only and offline.** The dashboard reads the configuration and the brand folder, never writes them ([[CON-002-dashboard-never-writes-to-the-wiki]]). After the first start it runs without network.

**Success metric(s).** A fresh starter kit on a clean Linux or macOS machine with Docker shows its dashboard after `make dev`, with no other step.

**Scope.** in: releases, the launcher, the metamodel version check, branding by configuration · out: Windows (for now), hosting for many users ([[CON-001-proof-of-concept-not-production-ready]]), assembling the Systems42 starter kit (moved to `meta#54`, [[FR-033-runnable-dashboard-in-the-starter-kit]] deprecated).

## Hierarchy

- **Parent:** none (epic).
- **Children:** projected from the `parent:` backlinks: [[FR-030-numbered-releases]], [[FR-031-branding-is-configuration]], [[FR-032-example-brands-to-try]], [[FR-033-runnable-dashboard-in-the-starter-kit]], [[FR-042-start-a-pinned-release-with-one-command]], [[FR-043-the-dashboard-checks-the-metamodel-version]], [[FR-045-a-prompt-template-for-a-brand]], [[FR-054-a-start-without-a-container-engine]], [[FR-055-an-installable-dashboard-app]].

> [!note] Open points
> None. Gernot Starke agreed Should for the epic and FR-030, FR-032, FR-033, and Must for FR-031, on 2026-11-13.

## History

> Raised by Gernot Starke on 2026-11-13 ([[SRC-019-the-dashboard-as-a-product]]). Shaped in seven questions ([[SRC-020-grilling-session-on-the-dashboard-as-a-product]]): GOAL-002 and a new goal, one epic with four features, three keys in `wiki.yaml`, Windows ignored for now, `./dashboard.sh local` as an unsupported fallback, no offline installation, and container images per release (DR-004).
> On 2026-11-17 he added the launcher, the metamodel version check and the prompt template for a brand, and kept the code in this repository ([[SRC-028-grilling-session-on-dashboard-distribution]]).
