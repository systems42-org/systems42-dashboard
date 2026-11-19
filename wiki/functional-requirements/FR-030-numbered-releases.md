---
id: FR-030
type: functional-requirement
title: Numbered releases
status: draft
created: 2026-11-13
updated: 2026-11-18
sources: ["[[SRC-019-the-dashboard-as-a-product]]", "[[SRC-020-grilling-session-on-the-dashboard-as-a-product]]", "[[SRC-029-grilling-session-on-the-published-image]]"]
related: ["[[DR-004-releases-are-container-images-pinned-per-wiki]]", "[[STK-012-maintainers]]"]
tags: ["functional-requirement", "product"]
stereotype: feature
parent: ["[[FR-029-the-dashboard-as-a-product]]"]
priority: Must
release: unscheduled
lane: backbone
order: 30
goal: ["[[GOAL-008-one-way-into-every-systems42-wiki]]"]
---

# Numbered releases

## Story

As a [[STK-010-operators|person who runs the dashboard]] I want **my wiki to name the dashboard release it uses**, so that **an update happens only when I ask for it**.

**PROBLEM / GOAL**

- Every release has a version number and release notes taken from `CHANGELOG.md`.
- Every release is published as a container image, `ghcr.io/systems42-org/dashboard:<version>`, that any Systems42 repository can run ([[DR-004-releases-are-container-images-pinned-per-wiki]]).
- Anyone can pull the image without an account or a login.
- The image runs on amd64 and arm64 machines.
- A wiki names its release in `_system/wiki.yaml` as `dashboard_version:`. It moves to a newer one only on purpose.
- A new release never changes a wiki that did not ask for it.
- The page footer shows the release that runs. When the wiki names another one, the footer says so.

**Success metric(s).** Changing `dashboard_version:` and running `make dev` again shows the new number in the footer. A wiki that names an older release keeps running it after a newer one is published. On a machine that is not logged in to any registry, `docker pull ghcr.io/systems42-org/dashboard:<version>` succeeds for every published release, on amd64 and on arm64.

**Scope.** in: version numbers, release notes, the published image, the version a wiki names · out: automatic updates, starting the image ([[FR-042-start-a-pinned-release-with-one-command]]).

## Hierarchy

- **Parent:** [[FR-029-the-dashboard-as-a-product]]
- **Children:** none.

## History

> Raised by Gernot Starke on 2026-11-13 ([[SRC-019-the-dashboard-as-a-product]]). The key `dashboard_version:` and its place in `wiki.yaml` were settled in question 3, how releases reach a wiki in question 7 ([[SRC-020-grilling-session-on-the-dashboard-as-a-product]], [[DR-004-releases-are-container-images-pinned-per-wiki]]).
> Changed on 2026-11-18: the published image, pulled without a login, for amd64 and arm64, and the priority Must instead of Should, because isaqb-atrium and meta hold no dashboard code any more ([[SRC-029-grilling-session-on-the-published-image]]).
