---
id: FR-059
type: functional-requirement
title: Downloads on the website
status: draft
created: 2026-11-21
updated: 2026-11-21
sources: ["[[SRC-037-a-public-website-for-the-dashboard]]", "[[SRC-038-grilling-session-on-the-public-website]]"]
related: ["[[FR-042-start-a-pinned-release-with-one-command]]", "[[FR-030-numbered-releases]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[CON-001-proof-of-concept-not-production-ready]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]"]
tags: ["functional-requirement", "website"]
notation: agile
level: feature
parent: ["[[FR-056-a-public-website-for-the-dashboard]]"]
priority: Should
release: unscheduled
lane: backbone
order: 59
goal: ["[[GOAL-002-show-what-systems42-can-do]]", "[[GOAL-008-one-way-into-every-systems42-wiki]]"]
---

# Downloads on the website

## Story

As a [[STK-010-operators|person who sets up a project wiki]] I want **one page with everything I need to run the dashboard**, so that **I can start it on my wiki without reading the repository**.

**PROBLEM / GOAL**

- **The launcher.** `dashboard.sh` to download ([[FR-042-start-a-pinned-release-with-one-command]]), with its SHA-256 checksum next to it.
- **The container image.** The image of the current release with the command to pull it, the processor types it supports (amd64, arm64), and that no registry login is needed.
- **Releases.** Links to the releases and the source on GitHub, and the command that moves a wiki to the newest release ([[FR-030-numbered-releases]]).
- **Commands to copy.** Getting the launcher with `curl`, and a minimal `_system/wiki.yaml`.
- **Platforms and limits.** Linux and macOS ([[CON-003-docker-is-the-supported-way-to-run-it]]), offline after the first start, no login, no write access to the wiki, for local reading and trusted workshop rooms ([[CON-001-proof-of-concept-not-production-ready]]).
- **Release notes.** Those of the newest releases, taken from `CHANGELOG.md`.

**Success metric(s).** The launcher downloaded from the page has the checksum the page shows. Copied into a Systems42 wiki that names the current release, it starts the dashboard.

**Scope.** in: the downloads page · out: an installer, package managers.

## Hierarchy

- **Parent:** [[FR-056-a-public-website-for-the-dashboard]]
- **Children:** none.

> [!note] Open points
> - The page offers Docker only. The start with uv and its wheel are missing ([issue #86](https://github.com/systems42-org/systems42-dashboard/issues/86)).

## History

> Stated by Gernot Starke on 2026-11-21 and read from the existing site ([[SRC-037-a-public-website-for-the-dashboard]]). Goals and priority agreed on 2026-11-21 ([[SRC-038-grilling-session-on-the-public-website]]).
