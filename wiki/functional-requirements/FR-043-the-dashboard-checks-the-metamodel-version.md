---
id: FR-043
type: functional-requirement
title: The dashboard checks the metamodel version
status: draft
created: 2026-11-17
updated: 2026-11-17
sources: ["[[SRC-027-dashboard-distribution-and-metamodel-contract]]", "[[SRC-028-grilling-session-on-dashboard-distribution]]"]
related: ["[[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]]", "[[FR-030-numbered-releases]]", "[[ISS-004-where-the-metamodel-declares-its-version]]", "[[CON-001-proof-of-concept-not-production-ready]]"]
tags: ["functional-requirement", "product"]
stereotype: feature
parent: ["[[FR-029-the-dashboard-as-a-product]]"]
priority: Should
release: unscheduled
lane: backbone
order: 43
goal: ["[[GOAL-008-one-way-into-every-systems42-wiki]]", "[[GOAL-001-trusted-answers]]"]
---

# The dashboard checks the metamodel version

## Story

As a [[STK-010-people-who-run-the-dashboard|person who runs the dashboard]] I want **to be told when the dashboard release does not support my wiki's metamodel version**, so that **I know why something may look wrong and what to do about it**.

**PROBLEM / GOAL**

- Every dashboard release states the range of metamodel versions it supports, in its release notes and on the Metamodel page.
- The dashboard reads the version that the metamodel of its repository declares.
- On a mismatch every page shows a notice in the footer, next to the dashboard version. The notice links to an explanation: the metamodel version of the repository, the versions this release supports, and what to do (name another `dashboard_version:`, or update the method in the repository).
- A metamodel that declares no version counts as a mismatch, with its own wording.
- The dashboard keeps showing the wiki. It never refuses to start over a mismatch.

**Success metric(s).** On a test repository whose metamodel version is outside the supported range, every page shows the notice, and the explanation names both versions.

**Scope.** in: the supported range, the check, the notice and its explanation · out: where Systems42 declares the version ([[ISS-004-where-the-metamodel-declares-its-version]]), migrating a wiki to another metamodel version.

## Hierarchy

- **Parent:** [[FR-029-the-dashboard-as-a-product]]
- **Children:** none.

> [!note] Open points
> Until [[ISS-004-where-the-metamodel-declares-its-version]] is answered, the dashboard reads `version:` from `_system/metamodel/meta-metamodel.md`.

## History

> Decided by Gernot Starke on 2026-11-17 ([[SRC-027-dashboard-distribution-and-metamodel-contract]]). Notice instead of refusal, and a missing version as a mismatch, in question 4 of [[SRC-028-grilling-session-on-dashboard-distribution]]. The priority follows the epic and was not asked separately.
