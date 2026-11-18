---
id: FR-044
type: functional-requirement
title: Sections come from the repository's metamodel
status: draft
created: 2026-11-17
updated: 2026-11-17
sources: ["[[SRC-027-dashboard-distribution-and-metamodel-contract]]", "[[SRC-028-grilling-session-on-dashboard-distribution]]"]
related: ["[[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]]", "[[FR-023-areas-and-sections-follow-the-tailoring]]", "[[CON-005-the-dashboard-works-on-systems42-derivatives-only]]", "[[STK-012-maintainers]]"]
tags: ["functional-requirement", "navigation"]
stereotype: feature
parent: ["[[FR-017-browse-by-area-and-section]]"]
priority: Must
release: unscheduled
lane: backbone
order: 44
goal: ["[[GOAL-008-one-way-into-every-systems42-wiki]]", "[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Sections come from the repository's metamodel

## Story

As a [[STK-011-people-who-set-up-a-project-wiki|person who sets up a project wiki]] I want **the dashboard to show the sections my repository's metamodel declares**, so that **a released dashboard fits my wiki without a code change**.

**PROBLEM / GOAL**

- The dashboard builds its section catalog from the framework blocks in `_system/metamodel/frameworks/` of the repository it runs on: each section's id, title, folders and scope.
- The dashboard code holds no list of sections ([[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]]).
- The three areas are fixed. Routes, colours and layout stay the dashboard's.

**Success metric(s).** On a test repository with one renamed section and one added section, the dashboard shows both on the first page, in the header and in the lists, without a code change.

**Scope.** in: sections and their folders · out: leaving sections out ([[FR-023-areas-and-sections-follow-the-tailoring]], which builds on this), type prefixes and labels (same constraint, not yet a requirement).

## Hierarchy

- **Parent:** [[FR-017-browse-by-area-and-section]]
- **Children:** none.

## History

> Decided by Gernot Starke on 2026-11-17 ([[SRC-027-dashboard-distribution-and-metamodel-contract]]). Must, because the isaqb-atrium showcase depends on it, question 5 of [[SRC-028-grilling-session-on-dashboard-distribution]]. On that day the three metamodels (meta, this repository, isaqb-atrium) declared the same sections A1 to A5, C1 to C7 and R1 to R6. They differed in the title of C6 and in the scope of A3 to A5.
