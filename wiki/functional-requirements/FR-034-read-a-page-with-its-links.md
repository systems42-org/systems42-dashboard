---
id: FR-034
type: functional-requirement
title: Read a page with its links
status: draft
created: 2026-11-13
updated: 2026-11-13
sources: ["[[SRC-021-read-a-page-with-its-links]]", "[[SRC-022-grilling-session-on-reading-a-page]]"]
related: ["[[FR-027-issues-on-the-page-they-affect]]", "[[FR-035-method-terms-lead-to-their-definition]]", "[[FR-020-know-where-you-are]]"]
tags: ["functional-requirement", "navigation"]
stereotype: feature
parent: ["[[FR-017-browse-by-area-and-section]]"]
priority: Must
release: unscheduled
lane: backbone
order: 34
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Read a page with its links

## Story

As a reader I want **one wiki page with its text, what it links to and what links to it**, so that **I understand the page and can follow its connections without asking anyone**.

**PROBLEM / GOAL**

- Every wiki page has a stable address that can be shared and bookmarked.
- The page head shows type, ID, status, created and updated dates, tags and sources.
- The body is rendered: every wikilink is a working link to its target, and diagrams written as `mermaid` blocks show as diagrams.
- Below the text, "Links to" and "Linked from" list the related pages, grouped by page type.
- A linked issue shows its status. A resolved issue never looks like an open one.

**Success metric(s).** On a test wiki, every wikilink on every page leads to an existing page or anchor entry, and every page appears under "Linked from" on each page it links to. A resolved issue in "Linked from" is visibly marked as resolved.

**Scope.** in: one page and its direct links · out: editing, comments.

## Hierarchy

- **Parent:** [[FR-017-browse-by-area-and-section]]
- **Children:** none.

## History

> Extracted from the dashboard code on 2026-11-10 ([[SRC-021-read-a-page-with-its-links]]) and rewritten as needs on 2026-11-13. Gernot Starke agreed the split and Must in question 2 of [[SRC-022-grilling-session-on-reading-a-page]].
