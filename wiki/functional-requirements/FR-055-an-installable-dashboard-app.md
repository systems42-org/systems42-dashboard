---
id: FR-055
type: functional-requirement
title: An installable dashboard app
status: draft
created: 2026-11-20
updated: 2026-11-20
sources: ["[[SRC-036-grilling-session-on-running-without-a-container-engine]]"]
related: ["[[FR-054-a-start-without-a-container-engine]]", "[[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]", "[[FR-043-the-dashboard-checks-the-metamodel-version]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[CON-005-the-dashboard-works-on-systems42-derivatives-only]]"]
tags: ["functional-requirement", "product"]
notation: agile
level: feature
parent: ["[[FR-029-the-dashboard-as-a-product]]"]
priority: Should
release: unscheduled
lane: backbone
order: 55
goal: ["[[GOAL-008-one-way-into-every-systems42-wiki]]"]
---

# An installable dashboard app

## Story

As a [[STK-010-operators|person who runs the dashboard]] inside a virtual machine I want **to install the dashboard as an app on macOS**, so that **I can show my wiki without Docker, uv or a terminal**.

**PROBLEM / GOAL**

- **Why.** As in [[FR-054-a-start-without-a-container-engine]]: inside a virtual machine no container engine runs. An app also needs no Python and no command line.
- **A second implementation.** The app is written in Go, next to the Python dashboard, and shows the same pages for the same wiki ([[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]).
- **macOS first.** Windows may follow.
- **One app for every wiki.** The app is installed once and shows any Systems42 wiki. When a wiki names another release in `dashboard_version:`, the app says so, as the dashboard does today, and shows the wiki anyway.
- **Read only.** The app writes nothing to the wiki ([[CON-002-dashboard-never-writes-to-the-wiki]]) and shows Systems42 derivatives only ([[CON-005-the-dashboard-works-on-systems42-derivatives-only]]).

**Success metric(s).** On a Mac without Docker, uv and Python, a person installs the app, opens a Systems42 wiki with it and sees the pages the Python dashboard of the same release shows.

**Scope.** in: the app for macOS, the same pages as the Python dashboard · out: Windows (for now), a different release per wiki, updates without being asked.

## Hierarchy

- **Parent:** [[FR-029-the-dashboard-as-a-product]]
- **Children:** none.

> [!note] Open points
> - Whether the app shows the pages in the browser or in a window of its own is not decided.
> - The plan is [issue #80](https://github.com/systems42-org/systems42-dashboard/issues/80).

## History

> Asked for by Gernot Starke on 2026-11-20. He chose one app that tells a differing release over an app that fetches the release each wiki names ([[SRC-036-grilling-session-on-running-without-a-container-engine]]). The priority is Claude's proposal.
