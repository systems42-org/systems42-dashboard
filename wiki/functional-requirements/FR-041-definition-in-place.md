---
id: FR-041
type: functional-requirement
title: Definition in place
status: draft
created: 2026-11-14
updated: 2026-11-14
sources: ["[[SRC-025-domain-terms-and-their-two-views]]", "[[SRC-026-grilling-session-on-domain-terms]]"]
related: ["[[FR-035-method-terms-lead-to-their-definition]]", "[[FR-034-read-a-page-with-its-links]]"]
tags: ["functional-requirement", "domain-terms"]
stereotype: feature
parent: ["[[FR-037-domain-terms]]"]
priority: Should
release: unscheduled
lane: backbone
order: 41
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Definition in place

## Story

As a [[STK-015-newcomers|newcomer]] I want **to read a term's definition where I meet the term**, so that **I keep reading without leaving the page**.

**PROBLEM / GOAL**

- On any page, hovering or focusing a link to a domain term shows its definition.
- It works by keyboard and by touch, not only with a mouse.
- The link still opens the term page.
- Method terms work the same way ([[FR-035-method-terms-lead-to-their-definition]]).

**Success metric(s).** On a test wiki, every link to a domain term carries its definition, and the definition shows on hover, on keyboard focus and on a tap.

**Scope.** in: links to domain terms · out: terms written as plain text without a link.

## Hierarchy

- **Parent:** [[FR-037-domain-terms]]
- **Children:** none.

## History

> From [[SRC-025-domain-terms-and-their-two-views]]. Should, in question 2 of [[SRC-026-grilling-session-on-domain-terms]].
