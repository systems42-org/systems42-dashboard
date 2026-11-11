---
id: FR-013
type: functional-requirement
title: Header and footer on every page
status: draft
created: 2026-11-11
updated: 2026-11-11
sources: ["[[SRC-010-header-and-footer-on-every-page]]", "[[SRC-011-grilling-session-on-header-and-footer]]"]
related: ["[[STK-015-newcomers]]", "[[FR-001-search-the-wiki]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]"]
tags: ["functional-requirement", "page-frame"]
stereotype: feature
parent: []
priority: Must
release: unscheduled
lane: backbone
order: 13
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Header and footer on every page

## Story

As a [[STK-015-newcomers]] **newcomer** I want **the same header and footer on every page, each with one job**, so that **I know where to look for content and where to look for facts about the dashboard itself**.

**PROBLEM / GOAL**

The header and the footer grew item by item. Until 2026-11-11 the footer mixed links to content, the state of the view and credits, and it repeated links the header had.

- Every page carries the same header and the same footer.
- The header leads to content.
- The footer holds formalities: the state of this view, the method behind the wiki and the technology of the dashboard.
- A link is in the header or in the footer, never in both.

**Success metric(s).** An automated test finds the five header entries on every page and no link to wiki content in the footer.

**Scope.** in: the header entries, the footer items and the connection dot · out: the search box ([[FR-001-search-the-wiki]]), the menu, the nickname of the browser tab, and rules for colours, type and logos.

## Hierarchy

- **Parent:** none.
- **Children:** [[FR-014-reach-the-main-content-from-the-header]], [[FR-015-read-the-formalities-in-the-footer]], [[FR-016-see-whether-the-page-is-still-connected]].

> [!note] Open points
> None.

## History

> Written from a conversation on the page frame on 2026-11-11 ([[SRC-010-header-and-footer-on-every-page]]). Sharpened with Gernot Starke in questions Q1 to Q5 ([[SRC-011-grilling-session-on-header-and-footer]]).
