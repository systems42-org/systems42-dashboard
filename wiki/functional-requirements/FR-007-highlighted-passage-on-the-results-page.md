---
id: FR-007
type: functional-requirement
title: Highlighted passage on the results page
status: draft
created: 2026-11-11
updated: 2026-11-11
sources: ["[[SRC-006-grilling-session-on-search]]"]
related: ["[[FR-005-reason-for-every-non-exact-hit]]"]
tags: ["functional-requirement", "search"]
stereotype: feature
parent: ["[[FR-001-search-the-wiki]]"]
priority: Should
release: unscheduled
lane: backbone
order: 7
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Highlighted passage on the results page

## Story

As a [[STK-014-domain-experts]] **domain expert** I want **each hit on the results page to show the sentence where my words matched**, so that **I often get the answer without opening the page**.

**PROBLEM / GOAL**

Today a hit shows its type, ID, title and a relevance band. The reader has to open pages to see whether they answer the question.

- Each hit on `/search` shows the sentence where the query matched, with the matching words highlighted.
- For a title hit, it shows the first sentence of the page.
- The popup shows no passage. It stays compact and quick to scan.

**Success metric(s).** On a fixed test wiki, every hit on `/search` for a body-text query shows a passage that contains the highlighted query word.

**Scope.** in: `/search` · out: the popup, and the reason note ([[FR-005-reason-for-every-non-exact-hit]]).

## Hierarchy

- **Parent:** [[FR-001-search-the-wiki]]
- **Children:** none.

> [!note] Open points
> None.

## History

> Decided in Q6 of [[SRC-006-grilling-session-on-search]], as a smaller form of the "answer instead of a list" idea from Q1.
