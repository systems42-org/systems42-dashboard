---
id: FR-031
type: functional-requirement
title: Branding is configuration
status: draft
created: 2026-11-13
updated: 2026-11-13
sources: ["[[SRC-019-the-dashboard-as-a-product]]", "[[SRC-020-grilling-session-on-the-dashboard-as-a-product]]"]
related: ["[[FR-032-example-brands-to-try]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[CON-001-proof-of-concept-not-production-ready]]"]
tags: ["functional-requirement", "product"]
stereotype: feature
parent: ["[[FR-029-the-dashboard-as-a-product]]"]
priority: Should
release: unscheduled
lane: backbone
order: 31
goal: ["[[GOAL-008-one-way-into-every-systems42-wiki]]", "[[GOAL-002-show-what-systems42-can-do]]"]
---

# Branding is configuration

## Story

As a [[STK-011-people-who-set-up-a-project-wiki|person who sets up a project wiki]] I want **to give the dashboard my project's look without touching its code**, so that **I can keep using every new release**.

**PROBLEM / GOAL**

- `brand:` in `_system/wiki.yaml` names an example brand ([[FR-032-example-brands-to-try]]) or a brand folder in the wiki's repository, such as `brand/`. Without it, the dashboard shows its default brand.
- A brand holds two marks (dark and light theme), a favicon and, optionally, an intro animation.
- `intro: on | off` switches the intro. When on, it shows at most once per browser tab, nothing under reduced motion, is done within about two seconds, ends on any click or key, and fetches nothing from the network.
- The dashboard only reads the brand folder ([[CON-002-dashboard-never-writes-to-the-wiki]]). A folder outside the repository, missing or incomplete shows the default brand, never an error page.
- Brand files are trusted content: the intro runs in every reader's browser. They are reviewed like code before they are committed.
- The name and the tagline stay in `_system/wiki.yaml`.

**Success metric(s).** Turning the intro off takes one changed setting and a reload. The home page then opens without it. A wiki's own brand folder shows its marks after one changed setting.

**Scope.** in: marks, favicon, intro, the switch · out: colours and layout of the dashboard itself.

## Hierarchy

- **Parent:** [[FR-029-the-dashboard-as-a-product]]
- **Children:** none.

## History

> Raised by Gernot Starke on 2026-11-13 ([[SRC-019-the-dashboard-as-a-product]]). The keys `brand:` and `intro:` were settled in question 3 ([[SRC-020-grilling-session-on-the-dashboard-as-a-product]]).
