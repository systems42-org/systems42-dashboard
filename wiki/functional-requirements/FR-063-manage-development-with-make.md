---
id: FR-063
type: functional-requirement
title: Manage development with make
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-041-managing-development-with-make]]", "[[SRC-042-grilling-session-on-development-with-make]]"]
related: ["[[STK-012-maintainers]]", "[[STK-010-operators]]", "[[FR-030-numbered-releases]]", "[[FR-042-start-a-pinned-release-with-one-command]]", "[[FR-054-a-start-without-a-container-engine]]", "[[FR-055-an-installable-dashboard-app]]", "[[FR-062-the-website-is-built-and-published-from-the-repository]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[CC-001-tests-of-the-python-dashboard-are-plain-scripts]]"]
tags: ["functional-requirement", "product"]
notation: agile
level: feature
parent: ["[[FR-029-the-dashboard-as-a-product]]"]
priority: Should
release: unscheduled
lane: backbone
order: 63
goal: []
---

# Manage development with make

## Story

As a [[STK-012-maintainers|maintainer]] I want **a short `make` target for each routine task of development**, so that **I run, test, preview and release the dashboard without looking up a script**.

**PROBLEM / GOAL**

- **Four task areas.** Each has its targets at the root of the repository:
  - run the dashboard: `dev`, `uv`, `app-start`, `down` ([[FR-042-start-a-pinned-release-with-one-command]], [[FR-054-a-start-without-a-container-engine]])
  - test and clean: `test`, `clean` ([[CC-001-tests-of-the-python-dashboard-are-plain-scripts]])
  - the public website: `site`, `site-show`, `site-down` ([[FR-062-the-website-is-built-and-published-from-the-repository]])
  - releases: `version`, `publish`, `app-bundle` ([[FR-030-numbered-releases]], [[FR-055-an-installable-dashboard-app]])
- **The list is in `make`.** `make` without a target prints every target with one line on what it does.
- **A thin wrapper.** A target calls one script. The logic is in `dashboard.sh`, in `dev.sh` and in the scripts under `site/`.
- **Two kinds of targets.** `dev`, `uv`, `down` and `clean` work in every Systems42 wiki, for the [[STK-010-operators|people who run a dashboard]]. The others work in the dashboard's repository only, and `make` says so.
- **Content is safe.** No target changes `wiki/` or `raw/` ([[CON-002-dashboard-never-writes-to-the-wiki]]). `clean` removes only what can be rebuilt.

**Success metric(s).** `make` lists every target of the `Makefile`. Each recipe is one call of a script. After `make clean`, `git status` shows no change in `wiki/`, `raw/`, `docs/` and `sandbox/`.

**Scope.** in: the targets of the four task areas, the help text · out: other commands of the launcher such as `logs`, `update`, `rebuild` and `local`, which are called on the script.

## Hierarchy

- **Parent:** [[FR-029-the-dashboard-as-a-product]]
- **Children:** none.

## History

> Raised by Gernot Starke on 2026-11-21 ([[SRC-041-managing-development-with-make]]). One feature that does not restate each target, and four task areas instead of every command: questions 1 and 2 of [[SRC-042-grilling-session-on-development-with-make]]. The source does not name `app-bundle`, which the `Makefile` has.
