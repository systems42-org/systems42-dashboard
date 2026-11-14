---
id: FR-040
type: functional-requirement
title: Two views of the same terms
status: draft
created: 2026-11-14
updated: 2026-11-14
sources: ["[[SRC-025-domain-terms-and-their-two-views]]", "[[SRC-026-grilling-session-on-domain-terms]]"]
related: ["[[QR-001-usable-on-phone-and-tablet]]", "[[FR-017-browse-by-area-and-section]]"]
tags: ["functional-requirement", "domain-terms"]
stereotype: feature
parent: ["[[FR-037-domain-terms]]"]
priority: Should
release: unscheduled
lane: backbone
order: 40
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Two views of the same terms

## Story

As a [[STK-002-business-analysts|business analyst]] I want **to see the whole vocabulary as a network and the modelled part as a data model**, so that **I understand both the language and the structure of the domain**.

**PROBLEM / GOAL**

- **Terminology network**, in Domain Terms (C5): all terms of every kind and the links between them.
- **Entity diagram**, the data model in Supporting Models (R4): only the structured terms, with their attributes and typed relationships.
- Both views read the same terms. Each links to the other.
- Every node opens its term page. Every node is also reachable as a text link on the same page ([[QR-001-usable-on-phone-and-tablet]]).

**Success metric(s).** On a test wiki, every term is a node in the network, every structured term is a node in the entity diagram, and every node opens its term page.

**Scope.** in: the two views · out: other diagrams, editing in a diagram.

## Hierarchy

- **Parent:** [[FR-037-domain-terms]]
- **Children:** none.

## History

> From [[SRC-025-domain-terms-and-their-two-views]]. Should in question 2, the data model stays in Supporting Models in question 4 of [[SRC-026-grilling-session-on-domain-terms]].
