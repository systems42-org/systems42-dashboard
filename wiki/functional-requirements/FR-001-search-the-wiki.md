---
id: FR-001
type: functional-requirement
title: Search the wiki
status: draft
created: 2026-11-11
updated: 2026-11-19
sources: ["[[SRC-005-search-the-wiki]]", "[[SRC-006-grilling-session-on-search]]", "[[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]"]
related: ["[[STK-001-readers]]", "[[STK-008-workshop-participants-and-facilitators]]", "[[CON-001-proof-of-concept-not-production-ready]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]"]
tags: ["functional-requirement", "search"]
notation: agile
level: epic
parent: []
priority: Must
release: unscheduled
lane: backbone
order: 1
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Search the wiki

## Epic: Summary

As a [[STK-001-readers|reader]] (development team, newcomer, domain expert) or [[STK-008-workshop-participants-and-facilitators|workshop participant]] I want **to find the right page from every page of the dashboard, even when I don't know the wiki's word for the thing**, so that **I get the answer without asking a colleague**.

**PROBLEM / GOAL**

A reader searches from every page of the dashboard, by ID, title or any word, in a popup while typing and on a full results page. Readers misspell terms, use other word forms and use words the wiki doesn't use. [[GOAL-003-answers-without-asking-a-colleague]] promises an answer "whether they know the right word or not". The features below meet that need with what the wiki itself knows: its aliases, its glossary and its links.

A reader reaches the search box from every page with the key ⌘K (Ctrl K on other systems). The box names the key.

**Success metric(s).**

- The example queries of every child feature pass an automated test on a fixed test wiki.
- In a workshop, the metric of [[GOAL-003-answers-without-asking-a-colleague]] holds: someone new to the wiki answers 8 of 10 prepared questions within 60 seconds each. Search is the main lever for it.

**Scope.** in: every wiki page, including pages of sections hidden in the view · out: meaning-based search with an embedding model, and answers written by an AI. Both are Won't, because they are not affordable for now (Gernot Starke, 2026-11-11). They would also need a network or a model download ([[CON-001-proof-of-concept-not-production-ready]]). Filter syntax such as `status:open` in the search box is out too, see [[FR-009-more-filters-on-the-full-results-page]].

## Hierarchy

- **Parent:** none (epic).
- **Children:** projected from the `parent:` backlinks. In order: [[FR-002-typos-and-word-forms]], [[FR-003-related-words-from-aliases-and-glossary]], [[FR-004-question-style-queries]], [[FR-005-reason-for-every-non-exact-hit]], [[FR-006-tags-and-fields-are-searched]], [[FR-007-highlighted-passage-on-the-results-page]], [[FR-008-related-pages-group]], [[FR-009-more-filters-on-the-full-results-page]].

> [!note] Open points
> None.

## History

> Extracted from the dashboard code on 2026-11-10 ([[SRC-005-search-the-wiki]]). Sharpened with Gernot Starke on 2026-11-11 in questions Q1 to Q10 ([[SRC-006-grilling-session-on-search]]).
>
> The key ⌘K was added on 2026-11-19 from meta DR-032, where it was built before it was required ([[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]). Peter Gerstbach decided to put it in this epic, not in a story of its own.
