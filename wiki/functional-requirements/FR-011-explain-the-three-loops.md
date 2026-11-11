---
id: FR-011
type: functional-requirement
title: Explain the three loops
status: draft
created: 2026-11-11
updated: 2026-11-11
sources: ["[[SRC-007-show-the-method]]", "[[SRC-008-grilling-session-on-showing-the-method]]"]
related: ["[[ISS-002-define-the-clarify-loop]]", "[[STK-015-newcomers]]"]
tags: ["functional-requirement", "method"]
stereotype: feature
parent: ["[[FR-010-show-the-method]]"]
priority: Should
release: unscheduled
lane: backbone
order: 11
goal: ["[[GOAL-002-show-what-systems42-can-do]]"]
---

# Explain the three loops

## Story

As a [[STK-022-prospective-adopters]] **prospective adopter** I want **the dashboard to explain the loops that keep the wiki alive**, so that **I understand how the pages came about and how they stay correct**.

**PROBLEM / GOAL**

The dashboard explains three loops by their principles, not their inner working, and how they feed each other:

- **Capture.** A human drops a raw source into the inbox. The AI grills it against the wiki, turns it into typed, linked pages and records where each page came from.
- **Inspect.** The wiki is checked against fixed rules, after each capture, at intervals or on request. Findings such as contradictions, broken links or untestable requirements become questions.
- **Clarify.** The principle is defined by the Systems42 team, see [[ISS-002-define-the-clarify-loop]].

Capture and inspect feed clarify, and clarify feeds the pages.

**Success metric(s).**

- The explanation fits on one screen and can be reached from every page of the dashboard.
- After reading it for at most 2 minutes, 4 of 5 test readers new to Systems42 name the three loops and say for each what goes in and what comes out. Checked in a workshop or demo, once [[ISS-002-define-the-clarify-loop]] is resolved.

**Scope.** in: principles of capture, inspect and clarify · out: the steps inside each loop.

## Hierarchy

- **Parent:** [[FR-010-show-the-method]]
- **Children:** none.

> [!note] Open points
> Clarify's principle waits for [[ISS-002-define-the-clarify-loop]].

## History

> Gernot Starke asked on 2026-11-11 to add the loops to the explanation. Capture and inspect follow `_system/workflows/capture.md` and `inspect.md`. Shaped in Q1 to Q4 of [[SRC-008-grilling-session-on-showing-the-method]].
