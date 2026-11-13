---
id: FR-033
type: functional-requirement
title: Runnable dashboard in the starter kit
status: draft
created: 2026-11-13
updated: 2026-11-13
sources: ["[[SRC-019-the-dashboard-as-a-product]]"]
related: ["[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[STK-022-prospective-adopters]]", "[[STK-008-workshop-participants]]"]
tags: ["functional-requirement", "product"]
stereotype: feature
parent: ["[[FR-029-the-dashboard-as-a-product]]"]
priority: Should
release: unscheduled
lane: backbone
order: 33
goal: ["[[GOAL-002-show-what-systems42-can-do]]", "[[GOAL-008-one-way-into-every-systems42-wiki]]"]
---

# Runnable dashboard in the starter kit

## Story

As a [[STK-022-prospective-adopters|prospective adopter]] I want **the Systems42 starter kit to start its dashboard right away**, so that **I see my first wiki without setting anything up**.

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
