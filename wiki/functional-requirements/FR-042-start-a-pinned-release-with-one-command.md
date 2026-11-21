---
id: FR-042
type: functional-requirement
title: Start a pinned release with one command
status: draft
created: 2026-11-17
updated: 2026-11-20
sources: ["[[SRC-027-dashboard-distribution-and-metamodel-contract]]", "[[SRC-028-grilling-session-on-dashboard-distribution]]", "[[SRC-036-grilling-session-on-running-without-a-container-engine]]"]
related: ["[[DR-004-releases-are-container-images-pinned-per-wiki]]", "[[FR-030-numbered-releases]]", "[[CON-005-the-dashboard-works-on-systems42-derivatives-only]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[FR-054-a-start-without-a-container-engine]]"]
tags: ["functional-requirement", "product"]
stereotype: feature
parent: ["[[FR-029-the-dashboard-as-a-product]]"]
priority: Should
release: unscheduled
lane: backbone
order: 42
goal: ["[[GOAL-008-one-way-into-every-systems42-wiki]]"]
---

# Start a pinned release with one command

## Story

As a [[STK-010-operators|person who runs the dashboard]] I want **one small launcher in my wiki that starts the release the wiki names**, so that **I get the dashboard without its code and update it with one command**.

**PROBLEM / GOAL**

- **The launcher is the only dashboard code in a wiki.** Currently it is `dashboard.sh`. A repository may add a Makefile that calls it.
- **It does four things.** It reads `dashboard_version:` from `_system/wiki.yaml`, starts that published image ([[DR-004-releases-are-container-images-pinned-per-wiki]]), waits until the dashboard answers, and opens the browser.
- **Zero-config start.** On a fresh Systems42 repository with default settings, running the launcher (or `make dev`) starts the dashboard with the default brand without editing any file. After the first start with network, it runs offline.
- **One mount.** It passes the repository root read-only. The dashboard writes nothing there ([[FR-046-shared-session-in-a-workshop]]). It finds everything else by convention ([[CON-005-the-dashboard-works-on-systems42-derivatives-only]]).
- **Update.** `./dashboard.sh update` sets `dashboard_version:` to the newest release. The launcher writes that line, not the dashboard, so [[CON-002-dashboard-never-writes-to-the-wiki]] holds.

**Success metric(s).** In a Systems42 derivative that holds no dashboard code except the launcher, `./dashboard.sh` shows the dashboard in the release the wiki names. After `./dashboard.sh update` and a restart, the footer shows the newest release.

**Scope.** in: the launcher, the mount, the update command · out: updates without being asked ([[FR-030-numbered-releases]]), running without Docker ([[FR-054-a-start-without-a-container-engine]]).

## Hierarchy

- **Parent:** [[FR-029-the-dashboard-as-a-product]]
- **Children:** none.

## History

> Proposed by Claude and agreed by Gernot Starke on 2026-11-17, question 2 of [[SRC-028-grilling-session-on-dashboard-distribution]]. On that day no image was published, and `dashboard.sh` had 200 lines, set eight paths and built the image from local code ([[SRC-027-dashboard-distribution-and-metamodel-contract]]).
