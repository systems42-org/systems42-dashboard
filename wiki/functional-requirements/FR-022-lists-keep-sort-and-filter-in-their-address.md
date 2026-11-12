---
id: FR-022
type: functional-requirement
title: Lists keep sort and filter in their address
status: draft
created: 2026-11-12
updated: 2026-11-12
sources: ["[[SRC-013-browse-by-area-and-section]]", "[[SRC-014-grilling-session-on-browsing]]"]
related: ["[[FR-021-sort-lists]]", "[[FR-023-areas-and-sections-follow-the-tailoring]]", "[[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]"]
tags: ["functional-requirement", "navigation"]
stereotype: feature
parent: ["[[FR-017-browse-by-area-and-section]]"]
priority: Should
release: unscheduled
lane: backbone
order: 22
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]", "[[GOAL-006-source-and-status-on-every-statement]]"]
---

# Lists keep sort and filter in their address

## Story

As a [[STK-001-product-owners]] **product owner** I want **to send a colleague the address of a list exactly as I sorted and filtered it**, so that **we both look at the same list**.

**PROBLEM / GOAL**

- Every list can be filtered by status, at least to "agreed only" ([[GOAL-006-source-and-status-on-every-statement]]).
- The list's address carries its sort order and its filter. A reader copies the address into a chat, an email or a ticket, or bookmarks it. Opening it shows exactly the same list, also after a reload and on another device.
- The dashboard sends nothing itself. There is no share button and no recipient ([[CON-002-dashboard-never-writes-to-the-wiki]]).
- A section the view has hidden stays reachable by its address ([[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]]).

**Success metric(s).** On a test wiki, a sorted and filtered list's address, opened in another browser, shows the same rows in the same order. "Agreed only" leaves only accepted pages.

**Scope.** in: every section list · out: sending from the dashboard, and filters other than status.

## Hierarchy

- **Parent:** [[FR-017-browse-by-area-and-section]]
- **Children:** none.

> [!note] Open points
> None.

## History

> First called "share". Renamed in [[SRC-014-grilling-session-on-browsing]], because the dashboard shares nothing itself: the address does.
