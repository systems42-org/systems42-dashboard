---
id: FR-058
type: functional-requirement
title: A demo to try without installing
status: draft
created: 2026-11-21
updated: 2026-11-21
sources: ["[[SRC-037-a-public-website-for-the-dashboard]]", "[[SRC-038-grilling-session-on-the-public-website]]"]
related: ["[[FR-010-show-the-method]]", "[[CON-001-proof-of-concept-not-production-ready]]", "[[FR-046-shared-session-in-a-workshop]]", "[[FR-001-search-the-wiki]]", "[[STK-012-maintainers]]"]
tags: ["functional-requirement", "website"]
notation: agile
level: feature
parent: ["[[FR-056-a-public-website-for-the-dashboard]]"]
priority: Must
release: unscheduled
lane: backbone
order: 58
goal: ["[[GOAL-002-show-what-systems42-can-do]]"]
---

# A demo to try without installing

## Story

As a [[STK-013-people-learning-or-presenting-systems42|person who considers using Systems42]] I want **to use the real dashboard on a real wiki in my browser**, so that **I judge it from a working example instead of a description**.

**PROBLEM / GOAL**

- **The real dashboard.** The demo is a snapshot made from the dashboard itself, not a rebuilt copy. What the demo shows is what a release shows.
- **No installation, no account.**
- **What works.** Reading every page, search, sorting and filtering lists, switching the theme, and the diagrams, including the metamodel and the term network.
- **What is left out.** Everything that needs a running dashboard: joining by QR code, the list of connected tabs, the View dialog, Reload and Disconnect all ([[FR-046-shared-session-in-a-workshop]]). The demo says that it is static and read-only.
- **A way back.** Every demo page links to the site, its documentation and its downloads.
- **Introduced on the overview.** The overview names the demo's wiki, says how many wiki pages and views it holds, and links to things worth trying: search, goals and the goal coverage matrix, requirements and open issues, the metamodel and graphs, the method overview.
- **Which wiki.** The demo shows the dashboard's own wiki. The [[STK-012-maintainers|maintainers]] can switch it to another Systems42 wiki without changing the site, and do so only when that wiki's owner agrees: the demo makes the whole wiki public.

**Success metric(s).** Every page the dashboard links for the demo's wiki opens in the demo. Search finds a page by its ID. No demo page calls a running dashboard.

**Scope.** in: the demo and its introduction on the overview · out: publishing any other wiki as a static site, the shared session.

## Hierarchy

- **Parent:** [[FR-056-a-public-website-for-the-dashboard]]
- **Children:** none.

> [!note] Open points
> - Nothing in the test suite builds the demo, so a change to a dashboard template can break it unnoticed ([issue #86](https://github.com/systems42-org/systems42-dashboard/issues/86)).

## History

> Stated by Gernot Starke on 2026-11-21 and read from the existing site ([[SRC-037-a-public-website-for-the-dashboard]]). He decided on 2026-11-21: the export is only the way this site gets its demo, the demo shows the dashboard's own wiki, and the maintainers decide on another one with its owner ([[SRC-038-grilling-session-on-the-public-website]]).
