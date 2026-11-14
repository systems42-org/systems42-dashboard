---
id: FR-037
type: functional-requirement
title: Domain terms
status: draft
created: 2026-11-14
updated: 2026-11-14
sources: ["[[SRC-025-domain-terms-and-their-two-views]]", "[[SRC-026-grilling-session-on-domain-terms]]"]
related: ["[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]", "[[FR-003-related-words-from-aliases-and-glossary]]", "[[FR-017-browse-by-area-and-section]]", "[[STK-015-newcomers]]", "[[STK-014-domain-experts]]", "[[STK-004-development-teams]]", "[[STK-002-business-analysts]]"]
tags: ["functional-requirement", "domain-terms"]
stereotype: epic
parent: []
priority: Must
release: unscheduled
lane: backbone
order: 37
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Domain terms

## Epic: Summary

As a [[STK-015-newcomers|newcomer]] I want **to find what a domain term means, what kind of term it is and how it relates to other terms**, so that **I understand the domain without asking a colleague**.

**PROBLEM / GOAL**

Systems42 plans one type, Domain Term, for what are now glossary terms and data-model entities (systems42-org/meta#36). A term without a stereotype is a defined business concept. A stereotype such as `entity` or `value-object` marks a term that is modelled structurally, with optional attributes and typed relationships. Systems42 defines the type, the dashboard shows it ([[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]).

These rules hold for every feature below:

- **One set of terms.** The list, the term pages and both views read the same domain terms.
- **Where they sit.** Domain Terms (C5) holds the list, the term pages and the terminology network. The data model, that is the entity diagram over the structured terms, stays in Supporting Models (R4). The two views link to each other.
- **Bridge until Systems42 has the type.** Until then, the dashboard shows glossary terms and data-model entities as one set of domain terms: a glossary term counts as a term without kind, a data-model entity as `entity`. Once Systems42 has the type, the dashboard reads it directly and the bridge goes. The wiki files are never changed by the dashboard.
- **Found by search.** Search finds a term by its name and its aliases ([[FR-003-related-words-from-aliases-and-glossary]]).

**Success metric(s).** On a test wiki with plain terms and structured terms, every term appears once in the list, has its page, and is a node in the terminology network. Every structured term is also a node in the entity diagram.

**Scope.** in: showing domain terms · out: defining the type, its fields or its stereotypes (Systems42), editing terms.

## Hierarchy

- **Parent:** none (epic).
- **Children:** projected from the `parent:` backlinks: [[FR-038-the-term-list]], [[FR-039-the-term-page]], [[FR-040-two-views-of-the-same-terms]], [[FR-041-definition-in-place]].

> [!note] Open points
> None. The type itself is decided in Systems42 (meta#36), where an implementation plan is posted.

## History

> Extracted from the code on 2026-11-10 and rewritten on 2026-11-14 for the planned merge of glossary terms and data models ([[SRC-025-domain-terms-and-their-two-views]]). Gernot Starke answered questions 1 to 4 ([[SRC-026-grilling-session-on-domain-terms]]): GOAL-003, one Must epic with four features, a bridge now, and the data model stays in Supporting Models.
