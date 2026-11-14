---
id: FR-039
type: functional-requirement
title: The term page
status: draft
created: 2026-11-14
updated: 2026-11-14
sources: ["[[SRC-025-domain-terms-and-their-two-views]]", "[[SRC-026-grilling-session-on-domain-terms]]"]
related: ["[[FR-034-read-a-page-with-its-links]]"]
tags: ["functional-requirement", "domain-terms"]
stereotype: feature
parent: ["[[FR-037-domain-terms]]"]
priority: Must
release: unscheduled
lane: backbone
order: 39
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# The term page

## Story

As a [[STK-004-development-teams|developer]] I want **one page per term with its meaning and, for a modelled term, its structure**, so that **I build what the domain means**.

**PROBLEM / GOAL**

- Every term page shows the definition, the kind and the aliases.
- A structured term also shows its attributes and its typed relationships with multiplicities, each related term as a link.
- The term's neighbours are one click away, in a small network of the term and its direct links.
- Everything else a page shows holds here too ([[FR-034-read-a-page-with-its-links]]).

**Success metric(s).** On a test wiki, an entity's page lists every attribute and relationship its page declares, and a plain term's page shows no empty structure sections.

**Scope.** in: one term and its direct links · out: editing.

## Hierarchy

- **Parent:** [[FR-037-domain-terms]]
- **Children:** none.

## History

> From [[SRC-025-domain-terms-and-their-two-views]]. Must, in question 2 of [[SRC-026-grilling-session-on-domain-terms]].
