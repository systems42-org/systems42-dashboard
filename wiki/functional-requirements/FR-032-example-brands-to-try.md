---
id: FR-032
type: functional-requirement
title: Example brands to try
status: draft
created: 2026-11-13
updated: 2026-11-19
sources: ["[[SRC-019-the-dashboard-as-a-product]]", "[[SRC-027-dashboard-distribution-and-metamodel-contract]]", "[[SRC-028-grilling-session-on-dashboard-distribution]]", "[[SRC-030-default-brand-and-instance-brands]]", "[[SRC-031-grilling-session-on-the-default-brand]]"]
related: ["[[FR-031-branding-is-configuration]]", "[[STK-013-people-learning-or-presenting-systems42]]", "[[FR-045-a-prompt-template-for-a-brand]]", "[[STK-012-maintainers]]"]
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

As a [[STK-011-people-who-set-up-a-project-wiki|person who sets up a project wiki]] I want **worked examples of a brand**, so that **I see what a brand can do before I make my own**.

**PROBLEM / GOAL**

- The dashboard ships one brand with marks, favicon and intro: **systems42**, the Peaks mark and its intro. It is the default brand and the model for others.
- The look of one wiki goes into that wiki's brand folder, never into the shipped brand. The shipped brand changes only when the [[STK-012-maintainers|maintainers]] want a new default for all wikis.
- The **atrium** brand, the iSAQB atrium mark and its intro, lives in the isaqb-atrium repository, which names its folder in `brand:` ([[FR-031-branding-is-configuration]]). It is the showcase for a repository's own brand.
- The **meta** brand, the Systems42 logo and its fly-in intro, lives in the meta repository in the same way.
- A project created from meta gets no brand folder and shows the default brand.
- All three follow the same rules as any wiki's own brand.

**Success metric(s).** isaqb-atrium shows its own mark and intro from a folder in its own repository, on a dashboard release that holds no atrium files.

**Scope.** in: the shipped systems42 brand, the atrium showcase, the meta brand · out: further examples.

## Hierarchy

- **Parent:** [[FR-029-the-dashboard-as-a-product]]
- **Children:** none.

## History

> Raised by Gernot Starke on 2026-11-13, "so users can experiment with these two" ([[SRC-019-the-dashboard-as-a-product]]).
> Changed on 2026-11-17: the atrium brand moves from the dashboard into isaqb-atrium, question 7 of [[SRC-028-grilling-session-on-dashboard-distribution]]. On that day it still sat in the dashboard code (`brands/atrium/`).
> Changed on 2026-11-19: release 0.11.3 had put meta's intro into the shipped brand, release 0.11.4 took it out again. The rule for the shipped brand, the meta brand and the default for new projects are questions 1, 2 and 4 of [[SRC-031-grilling-session-on-the-default-brand]].
