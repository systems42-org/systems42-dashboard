---
id: FR-026
type: functional-requirement
title: Issues carry a category
status: draft
created: 2026-11-12
updated: 2026-11-12
sources: ["[[SRC-015-see-what-is-still-open]]", "[[SRC-016-grilling-session-on-open-issues]]"]
related: ["[[FR-025-issue-list-with-filters]]", "[[FR-017-browse-by-area-and-section]]", "[[STK-001-product-owners]]"]
tags: ["functional-requirement", "issues"]
stereotype: feature
parent: ["[[FR-024-see-what-is-still-open]]"]
priority: Should
release: unscheduled
lane: backbone
order: 26
goal: ["[[GOAL-006-source-and-status-on-every-statement]]"]
---

# Issues carry a category

## Story

As a [[STK-001-product-owners|product owner]] I want **every issue to show which part of the work it touches**, so that **I hand it to the right people**.

**PROBLEM / GOAL**

- Every issue has exactly one category. If it touches two, its author picks the one where it has to be answered.
- The categories are a fixed list:
  - **requirements**, **architecture**, **commons**: the three areas ([[FR-017-browse-by-area-and-section]]).
  - **content**: housekeeping of the wiki itself, such as broken links, duplicates or stale pages.
  - **orga**: who decides, budget, schedule.
  - **systems42**: Systems42 itself, such as its metamodel, templates or loops.
- The category is not the kind. The kind says what sort of problem an issue is (question, contradiction, gap, ambiguity, risk). A risk is a kind, not a category.
- The issue list and each issue page show the category ([[FR-025-issue-list-with-filters]]).

**Success metric(s).** On a test wiki, every issue shows one category from the list, and filtering by a category leaves only its issues.

**Scope.** in: every issue · out: several categories per issue, and categories a project defines itself.

## Hierarchy

- **Parent:** [[FR-024-see-what-is-still-open]]
- **Children:** none.

> [!note] Open points
> None. The `category:` field is in the issue template and the metamodel since PR #11, together with `owner:` ([[FR-028-who-answers-an-issue]]).

## History

> Gernot Starke named the categories requirements, architecture, commons, content and orga, and added systems42 ([[SRC-015-see-what-is-still-open]]). "Commons" is the name of the area, kept by Gernot Starke on 2026-11-12. One category per issue, Should, in Q2 and Q4 of [[SRC-016-grilling-session-on-open-issues]].
