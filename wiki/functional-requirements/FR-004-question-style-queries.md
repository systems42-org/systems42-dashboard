---
id: FR-004
type: functional-requirement
title: Question-style queries
status: draft
created: 2026-11-11
updated: 2026-11-11
sources: ["[[SRC-006-grilling-session-on-search]]"]
related: ["[[FR-005-reason-for-every-non-exact-hit]]"]
tags: ["functional-requirement", "search"]
stereotype: feature
parent: ["[[FR-001-search-the-wiki]]"]
priority: Must
release: unscheduled
lane: backbone
order: 4
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Question-style queries

## Story

As a [[STK-008-workshop-participants]] **workshop participant** I want **to type my question as I would ask it**, so that **search finds the answer without me guessing keywords**.

**PROBLEM / GOAL**

Readers often type a question, such as `who starts the app`. Its filler words must not stop the search. The rule:

1. Common English filler words don't count: `who`, `what`, `how`, `the`, `a`, `is`, `does`, `of`, `to` and the like. If a query has nothing but filler words, they count.
2. Pages containing every remaining word come first, whether exact, as a typo, as a word form or via an alias.
3. Pages containing only some of the words follow, ranked by how many they contain, each with a note such as "matches 2 of 3 words". They rank below every page that contains all words.

A short query stays precise, and a question still finds something.

**Success metric(s).** On a fixed test wiki:

- `who starts the app` finds the Keyholder page in the top 3 of the popup.
- For a two-word query, a page with both words ranks above a page with one, and the second shows "matches 1 of 2 words".

**Scope.** in: every query in the popup and on `/search` · out: understanding the meaning of a question (Won't, see [[FR-001-search-the-wiki]]).

## Hierarchy

- **Parent:** [[FR-001-search-the-wiki]]
- **Children:** none.

> [!note] Open points
> None.

## History

> Found while writing the test table in Q8, then decided in Q9 of [[SRC-006-grilling-session-on-search]].
