---
id: FR-045
type: functional-requirement
title: A prompt template for a brand
status: draft
created: 2026-11-17
updated: 2026-11-17
sources: ["[[SRC-027-dashboard-distribution-and-metamodel-contract]]", "[[SRC-028-grilling-session-on-dashboard-distribution]]"]
related: ["[[FR-031-branding-is-configuration]]", "[[FR-032-example-brands-to-try]]"]
tags: ["functional-requirement", "product"]
stereotype: feature
parent: ["[[FR-029-the-dashboard-as-a-product]]"]
priority: Could
release: unscheduled
lane: backbone
order: 45
goal: ["[[GOAL-008-one-way-into-every-systems42-wiki]]"]
---

# A prompt template for a brand

## Story

As a [[STK-010-operators|person who sets up a project wiki]] I want **a ready prompt that makes an AI produce a brand folder for my project**, so that **my logo and intro meet the dashboard's rules at the first try**.

**PROBLEM / GOAL**

- The dashboard documentation holds a prompt template for a brand: two marks, a favicon and an intro animation.
- The template states the rules a brand must meet: file names and formats, sizes, colours for both themes, and the intro rules of [[FR-031-branding-is-configuration]].
- The in-app help links to it.

**Success metric(s).** A brand folder produced with the template alone is accepted by the dashboard without a warning.

**Scope.** in: the template, its place in the documentation, the link from the help · out: producing a brand inside the dashboard.

## Hierarchy

- **Parent:** [[FR-029-the-dashboard-as-a-product]]
- **Children:** none.

## History

> Raised by Gernot Starke on 2026-11-17 ([[SRC-027-dashboard-distribution-and-metamodel-contract]]). Could, because the existing brands already serve as worked examples, question 7 of [[SRC-028-grilling-session-on-dashboard-distribution]].
