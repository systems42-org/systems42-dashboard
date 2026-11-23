---
id: FR-032
type: functional-requirement
title: Example brands to try
status: draft
created: 2026-11-13
updated: 2026-11-23
sources: ["[[SRC-019-the-dashboard-as-a-product]]", "[[SRC-027-dashboard-distribution-and-metamodel-contract]]", "[[SRC-028-grilling-session-on-dashboard-distribution]]", "[[SRC-030-default-brand-and-instance-brands]]", "[[SRC-031-grilling-session-on-the-default-brand]]", "[[SRC-053-the-chart-mark]]", "[[SRC-054-grilling-session-on-the-chart-mark]]"]
related: ["[[FR-031-branding-is-configuration]]", "[[STK-013-people-learning-or-presenting-systems42]]", "[[FR-045-a-prompt-template-for-a-brand]]", "[[STK-012-maintainers]]"]
tags: ["functional-requirement", "product"]
notation: agile
level: feature
parent: ["[[FR-029-the-dashboard-as-a-product]]"]
priority: Should
release: unscheduled
lane: backbone
order: 32
goal: ["[[GOAL-002-show-what-systems42-can-do]]"]
---

# Example brands to try

## Story

As a [[STK-010-operators|person who sets up a project wiki]] I want **worked examples of a brand**, so that **I see what a brand can do before I make my own**.

**PROBLEM / GOAL**

- The dashboard ships one brand with marks, favicon and intro: **systems42**, the Chart mark and its intro. It is the default brand and the model for others.
- The Chart mark is an axis with six columns, each a Requirements block and an Architecture block, coloured by the theme tokens of these two areas. The favicon reduces it to three solid columns. The intro draws the axis, then grows the columns from left to right.
- Outside the dashboard, the brand page `docs/brand/` holds a lockup: the mark with the wordmark "systems42 DASHBOARD". The dashboard never shows it.
- The look of one wiki goes into that wiki's brand folder, never into the shipped brand. The shipped brand changes only when the [[STK-012-maintainers|maintainers]] want a new default for all wikis.
- A wiki with no brand folder shows the shipped default brand without extra setup ([[FR-031-branding-is-configuration]]).
- External repositories serve as reference examples outside this product: **atrium** lives in `isaqb-atrium` and **meta** lives in `systems42-org/meta`, each configured via `brand:` ([[FR-031-branding-is-configuration]]).

**Success metric(s).** A dashboard release ships the `systems42` brand with dark/light marks, favicon and intro, holds no instance-specific brand files, and loads an external repository's `brand/` folder cleanly.

**Scope.** in: the shipped `systems42` default brand · out: instance brands owned by other repositories (`atrium`, `meta` and project wikis).

## Hierarchy

- **Parent:** [[FR-029-the-dashboard-as-a-product]]
- **Children:** none.

## History

> Raised by Gernot Starke on 2026-11-13, "so users can experiment with these two" ([[SRC-019-the-dashboard-as-a-product]]).
> Changed on 2026-11-17: the atrium brand moves from the dashboard into isaqb-atrium, question 7 of [[SRC-028-grilling-session-on-dashboard-distribution]]. On that day it still sat in the dashboard code (`brands/atrium/`).
> Changed on 2026-11-19: release 0.11.3 had put meta's intro into the shipped brand, release 0.11.4 took it out again. The rule for the shipped brand, the meta brand and the default for new projects are questions 1, 2 and 4 of [[SRC-031-grilling-session-on-the-default-brand]].
> Changed on 2026-11-20: scope trimmed to the shipped default `systems42` brand only, keeping `atrium` and `meta` as external examples.
> Changed on 2026-11-23: the Chart mark replaces the Peaks mark ([[SRC-053-the-chart-mark]]). Colours, lockup, favicon and intro were settled in questions 1 to 9 of [[SRC-054-grilling-session-on-the-chart-mark]].
