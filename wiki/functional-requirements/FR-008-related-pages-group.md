---
id: FR-008
type: functional-requirement
title: Related pages group
status: draft
created: 2026-11-11
updated: 2026-11-11
sources: ["[[SRC-006-grilling-session-on-search]]"]
related: ["[[FR-003-related-words-from-aliases-and-glossary]]", "[[FR-005-reason-for-every-non-exact-hit]]"]
tags: ["functional-requirement", "search"]
stereotype: feature
parent: ["[[FR-001-search-the-wiki]]"]
priority: Should
release: unscheduled
lane: backbone
order: 8
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Related pages group

## Story

As a [[STK-015-newcomers]] **newcomer** I want **the results page to show the pages linked to my best hits**, so that **I find the answer even when it sits one link away from the words I typed**.

**PROBLEM / GOAL**

The answer is often on a page next to the hit, such as the constraint behind a requirement or the stakeholder behind a goal. The wiki's links already know these neighbours.

- Only strong hits count, meaning title or alias hits. A page that only mentions the word somewhere pulls in no neighbours.
- Neighbours are one link step away, in either direction.
- They show in their own group, "Related pages", below all real hits, never mixed in.
- At most 5. A page that is already a hit is not repeated.
- Each one carries its reason, such as "linked from STK-023" ([[FR-005-reason-for-every-non-exact-hit]]).
- The popup shows no related pages.

**Success metric(s).** On a fixed test wiki, a query that hits page P in its title shows P's neighbours under "Related pages": at most 5, none of them a hit already, and each with its reason. The popup for the same query shows none.

**Scope.** in: `/search` · out: neighbours further than one link step, and the popup.

## Hierarchy

- **Parent:** [[FR-001-search-the-wiki]]
- **Children:** none.

> [!note] Open points
> None.

## History

> Decided in Q7 of [[SRC-006-grilling-session-on-search]]. The group is kept separate so it can be dropped without touching the ranking.
