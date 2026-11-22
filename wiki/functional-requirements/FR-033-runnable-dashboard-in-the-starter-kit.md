---
id: FR-033
type: functional-requirement
title: Runnable dashboard in the starter kit
status: deprecated
created: 2026-11-13
updated: 2026-11-20
sources: ["[[SRC-019-the-dashboard-as-a-product]]"]
related: ["[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]", "[[FR-042-start-a-pinned-release-with-one-command]]", "[[STK-008-workshop-participants-and-facilitators]]"]
tags: ["functional-requirement", "product"]
notation: agile
level: feature
parent: ["[[FR-029-the-dashboard-as-a-product]]"]
priority: Should
release: unscheduled
lane: backbone
order: 33
goal: ["[[GOAL-002-show-what-systems42-can-do]]", "[[GOAL-008-one-way-into-every-systems42-wiki]]"]
---

# Runnable dashboard in the starter kit

> [!note] Deprecated (2026-11-20)
> Assembling the Systems42 starter kit belongs to `systems42-org/meta` ([meta issue #54](https://github.com/systems42-org/meta/issues/54)), not to the dashboard repository. The dashboard's own side (starting with one command and default settings without editing any file) is covered by [[FR-042-start-a-pinned-release-with-one-command]], [[FR-031-branding-is-configuration]] and [[QR-002-runs-alike-on-linux-and-macos]].

## Story

As a [[STK-013-people-learning-or-presenting-systems42|person learning Systems42]] I want **the Systems42 starter kit to start its dashboard right away**, so that **I see my first wiki without setting anything up**.

**PROBLEM / GOAL**

- The Systems42 starter kit, still to be designed, contains a runnable dashboard with a default configuration.
- A fresh starter kit starts with `make dev` and shows its wiki with the default brand, without editing any file.
- For a workshop, participants start it once with network beforehand. After that it runs offline.

**Success metric(s).** On a clean Linux or macOS machine with Docker, a fresh starter kit shows its dashboard after `make dev`, with no other step.

**Scope.** in: the dashboard part of the starter kit · out: the rest of the starter kit, installing without network.

## Hierarchy

- **Parent:** [[FR-029-the-dashboard-as-a-product]]
- **Children:** none.

## History

> Raised by Gernot Starke on 2026-11-13 ([[SRC-019-the-dashboard-as-a-product]]). No offline installation for now, question 6 of [[SRC-020-grilling-session-on-the-dashboard-as-a-product]].
