---
id: FR-038
type: functional-requirement
title: The term list
status: draft
created: 2026-11-14
updated: 2026-11-14
sources: ["[[SRC-025-domain-terms-and-their-two-views]]", "[[SRC-026-grilling-session-on-domain-terms]]"]
related: ["[[FR-021-sort-lists]]", "[[FR-022-lists-keep-sort-and-filter-in-their-address]]"]
tags: ["functional-requirement", "domain-terms"]
stereotype: feature
parent: ["[[FR-037-domain-terms]]"]
priority: Must
release: unscheduled
lane: backbone
order: 38
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# The term list

## Story

As a [[STK-014-domain-experts|domain expert]] I want **one list of all domain terms with their kind**, so that **I see the whole vocabulary and find the modelled terms quickly**.

**PROBLEM / GOAL**

- Domain Terms (C5) lists every domain term with name, definition, kind, status and number of links.
- The kind is empty for a plain term, or the term's stereotype, such as entity or value object.
- The list sorts and filters like every list ([[FR-021-sort-lists]], [[FR-022-lists-keep-sort-and-filter-in-their-address]]), and also filters by kind.

**Success metric(s).** On a test wiki, filtering by `entity` leaves exactly the entities, and filtering by "no kind" leaves exactly the plain terms.

**Scope.** in: the list · out: editing terms.

## Hierarchy

- **Parent:** [[FR-037-domain-terms]]
- **Children:** none.

## History

> From [[SRC-025-domain-terms-and-their-two-views]]. Must, in question 2 of [[SRC-026-grilling-session-on-domain-terms]].
