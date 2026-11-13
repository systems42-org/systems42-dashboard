---
id: FR-032
type: functional-requirement
title: Example brands to try
status: draft
created: 2026-11-13
updated: 2026-11-13
sources: ["[[SRC-019-the-dashboard-as-a-product]]"]
related: ["[[FR-031-branding-is-configuration]]", "[[STK-013-people-learning-or-presenting-systems42]]"]
tags: ["functional-requirement", "product"]
stereotype: feature
parent: ["[[FR-029-the-dashboard-as-a-product]]"]
priority: Should
release: unscheduled
lane: backbone
order: 32
goal: ["[[GOAL-002-show-what-systems42-can-do]]"]
---

# Example brands to try

## Story

As a [[STK-011-people-who-set-up-a-project-wiki|person who sets up a project wiki]] I want **ready brands to switch between**, so that **I see what a brand can do before I make my own**.

**PROBLEM / GOAL**

- The dashboard ships two example brands, each with marks, favicon and intro:
  - **systems42**: the Peaks mark and its intro. This is the default brand.
  - **atrium**: the iSAQB atrium mark and its intro.
- Changing `brand:` in `_system/wiki.yaml` switches between them ([[FR-031-branding-is-configuration]]).
- Each example follows the same rules as a wiki's own brand, so it also serves as a model.

**Success metric(s).** Switching from the systems42 brand to the atrium brand takes one changed setting and a reload. The atrium mark and intro then show.

**Scope.** in: the two example brands · out: further examples.

## Hierarchy

- **Parent:** [[FR-029-the-dashboard-as-a-product]]
- **Children:** none.

## History

> Raised by Gernot Starke on 2026-11-13, "so users can experiment with these two" ([[SRC-019-the-dashboard-as-a-product]]).
