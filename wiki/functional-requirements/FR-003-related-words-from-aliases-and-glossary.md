---
id: FR-003
type: functional-requirement
title: Related words from aliases and the glossary
status: draft
created: 2026-11-11
updated: 2026-11-11
sources: ["[[SRC-006-grilling-session-on-search]]"]
related: ["[[FR-005-reason-for-every-non-exact-hit]]", "[[STK-023-keyholder]]"]
tags: ["functional-requirement", "search"]
stereotype: feature
parent: ["[[FR-001-search-the-wiki]]"]
priority: Must
release: unscheduled
lane: backbone
order: 3
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Related words from aliases and the glossary

## Story

As a [[STK-015-newcomers]] **newcomer** I want **search to understand my word even when the wiki uses another one**, so that **I land on the right page without knowing the project's language**.

**PROBLEM / GOAL**

A reader often names a thing differently from the wiki. The wiki already knows the other names: every page can list `aliases:`, and glossary terms list their synonyms.

- A query word that matches an alias of a page finds that page. `Jedi Master` finds the Keyholder page.
- A glossary term's name and its aliases count as one word for the whole search. A query for an alias also finds every page that uses the term's name.
- An alias hit ranks below an exact hit for the same query.

The related words come only from the wiki itself, so every hit can be traced. The value grows with the glossary, which is still empty today.

**Success metric(s).** On a fixed test wiki, each query returns the expected page in the top 3 of the popup:

- `Jedi Master` finds the Keyholder page.
- A query for a glossary alias finds a page that uses only the term's name.

**Scope.** in: `aliases:` of every page, glossary terms and their aliases · out: synonyms from outside the wiki, such as an external thesaurus or a language model (Won't, see [[FR-001-search-the-wiki]]).

## Hierarchy

- **Parent:** [[FR-001-search-the-wiki]]
- **Children:** none.

> [!note] Open points
> None.

## History

> Chosen in Q1 and Q2 of [[SRC-006-grilling-session-on-search]] as the core of the "wow". It was option A, against an embedding model and AI answers.
