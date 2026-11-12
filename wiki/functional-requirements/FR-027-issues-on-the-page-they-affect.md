---
id: FR-027
type: functional-requirement
title: Issues on the page they affect
status: draft
created: 2026-11-12
updated: 2026-11-12
sources: ["[[SRC-015-see-what-is-still-open]]", "[[SRC-016-grilling-session-on-open-issues]]"]
related: ["[[FR-025-issue-list-with-filters]]", "[[STK-004-development-teams]]", "[[STK-019-auditors-and-quality-assurance]]"]
tags: ["functional-requirement", "issues"]
stereotype: feature
parent: ["[[FR-024-see-what-is-still-open]]"]
priority: Must
release: unscheduled
lane: backbone
order: 27
goal: ["[[GOAL-006-source-and-status-on-every-statement]]"]
---

# Issues on the page they affect

## Story

As a [[STK-004-development-teams|developer]] I want **a page to show the open issues that point at it**, so that **I know how firm it is before I build on it**.

**PROBLEM / GOAL**

- Every page shows the issues that point at it, open ones first, each with its status and severity.
- Each issue opens its page.
- A page with no open issue says so.

**Success metric(s).** On a test wiki, every page shows exactly the issues that link to it, and closing an issue in the wiki moves it behind the open ones after a reload.

**Scope.** in: every wiki page · out: issues that only mention a page without linking it.

## Hierarchy

- **Parent:** [[FR-024-see-what-is-still-open]]
- **Children:** none.

> [!note] Open points
> None.

## History

> Must in Q4 of [[SRC-016-grilling-session-on-open-issues]]. The section count moved to [[FR-019-section-at-a-glance]] in Q1.
