---
id: FR-005
type: functional-requirement
title: Reason for every non-exact hit
status: draft
created: 2026-11-11
updated: 2026-11-11
sources: ["[[SRC-006-grilling-session-on-search]]"]
related: ["[[FR-002-typos-and-word-forms]]", "[[FR-003-related-words-from-aliases-and-glossary]]", "[[FR-004-question-style-queries]]", "[[FR-008-related-pages-group]]", "[[GOAL-001-trusted-answers]]"]
tags: ["functional-requirement", "search"]
stereotype: feature
parent: ["[[FR-001-search-the-wiki]]"]
priority: Must
release: unscheduled
lane: backbone
order: 5
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Reason for every non-exact hit

## Story

As a [[STK-004-development-teams]] **developer** I want **to see why a hit is in the list when it doesn't contain my exact words**, so that **I trust the hit instead of taking it for a mistake**.

**PROBLEM / GOAL**

A typo hit or an alias hit looks wrong if nothing explains it. Without the reason, the smarter search costs trust. The vision promises trusted answers ([[GOAL-001-trusted-answers]]).

Every hit that is not an exact match carries a short note, in the popup and on `/search`:

- "typo: keyholdr → Keyholder" ([[FR-002-typos-and-word-forms]])
- "word form: starts → started" ([[FR-002-typos-and-word-forms]])
- "via alias of Keyholder" ([[FR-003-related-words-from-aliases-and-glossary]])
- "matches 2 of 3 words" ([[FR-004-question-style-queries]])
- "linked from STK-023" ([[FR-008-related-pages-group]])

An exact hit carries no note.

**Success metric(s).** On a fixed test wiki, every non-exact hit of the example queries in the sibling features carries the matching note, and no exact hit carries one.

**Scope.** in: popup and `/search` · out: the highlighted passage, see [[FR-007-highlighted-passage-on-the-results-page]].

## Hierarchy

- **Parent:** [[FR-001-search-the-wiki]]
- **Children:** none.

> [!note] Open points
> None.

## History

> Decided in Q6 of [[SRC-006-grilling-session-on-search]]. Made a Must in Q10, because an unexplained hit looks broken.
