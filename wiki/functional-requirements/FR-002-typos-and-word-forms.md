---
id: FR-002
type: functional-requirement
title: Typos and word forms
status: draft
created: 2026-11-11
updated: 2026-11-11
sources: ["[[SRC-005-search-the-wiki]]", "[[SRC-006-grilling-session-on-search]]"]
related: ["[[FR-005-reason-for-every-non-exact-hit]]", "[[DR-001-english-brief-plain-writing]]"]
tags: ["functional-requirement", "search"]
stereotype: feature
parent: ["[[FR-001-search-the-wiki]]"]
priority: Must
release: unscheduled
lane: backbone
order: 2
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Typos and word forms

## Story

As a [[STK-015-newcomers]] **newcomer** I want **search to forgive a typo or another form of the word**, so that **I find the page even when I spell the term wrong**.

**PROBLEM / GOAL**

Today `keyholdr` finds nothing, and `requirement` misses pages that only say `requirements`. The rule:

- Words of 3 letters or fewer, and IDs such as `STK-023`, match exactly or as a prefix. No tolerance.
- Words of 4 to 7 letters allow one wrong, missing or extra letter.
- Words of 8 letters or more allow two.
- Common English endings count as the same word: `requirement` and `requirements`, `starts` and `started`.
- An exact hit always ranks above a typo or word-form hit, so a typo never pushes a correct match down.

**Success metric(s).** On a fixed test wiki, each query returns the expected page in the top 3 of the popup:

- `keyholder` finds the Keyholder page in first place.
- `keyholdr` finds the Keyholder page.
- `stakholdrs` finds a stakeholder page.
- `requirement engineer` finds the requirements engineers page.
- `STK-02` finds STK-020 to STK-023.
- `test` ranks pages containing `test` above pages that only contain `text`.

**Scope.** in: every query word, in all searched text · out: word forms of other languages, because the wiki is English ([[DR-001-english-brief-plain-writing]]).

## Hierarchy

- **Parent:** [[FR-001-search-the-wiki]]
- **Children:** none.

> [!note] Open points
> None.

## History

> The gap "no tolerance for typing errors or word forms" came from [[SRC-005-search-the-wiki]]. The rule was set in Q3 of [[SRC-006-grilling-session-on-search]].
