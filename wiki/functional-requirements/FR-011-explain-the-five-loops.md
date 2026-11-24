---
id: FR-011
type: functional-requirement
title: Explain the five loops
status: draft
created: 2026-11-11
updated: 2026-11-24
sources: ["[[SRC-007-show-the-method]]", "[[SRC-008-grilling-session-on-showing-the-method]]", "[[SRC-055-recovery-report-systems42-dashboard]]", "[[SRC-056-closing-round-on-recovery-report]]"]
related: ["[[ISS-002-define-the-clarify-loop]]", "[[STK-001-readers]]"]
tags: ["functional-requirement", "method"]
notation: agile
level: feature
parent: ["[[FR-010-show-the-method]]"]
priority: Should
release: unscheduled
lane: backbone
order: 11
goal: ["[[GOAL-002-show-what-systems42-can-do]]"]
---

# Explain the five loops

## Story

As a [[STK-013-people-learning-or-presenting-systems42|person learning Systems42]] I want **the dashboard to explain the five loops that keep the wiki alive**, so that **I understand how pages are captured, checked, clarified and implemented, and how existing code can add knowledge**.

**PROBLEM / GOAL**

The dashboard explains the five current Systems42 loops by their principles, not their inner workings, and how they feed each other:

- **Capture.** A human drops a raw source into the inbox. The AI grills it against the wiki, turns it into typed, linked pages and records where each page came from.
- **Inspect.** The wiki is checked against fixed rules, after each capture, at intervals or on request. Findings such as contradictions, broken links or untestable requirements become questions.
- **Clarify.** Resolve an open Issue with the human and update the affected requirements ([[clarify]]).
- **Implement.** Implement a human-selected functional requirement and record delivery evidence ([[implement]]).
- **Recover.** Read existing code at a fixed revision and write a report of abstractions, evidence and gaps for capture ([[recover]]).

Capture and Recover add knowledge to the wiki. Inspect finds questions for Clarify. Clarify updates the requirements, which Implement uses to change the software.

**Success metric(s).**

- The explanation fits on one screen and can be reached from every page of the dashboard.
- After reading it for at most 2 minutes, 4 of 5 test readers new to Systems42 name the five loops and say what each one contributes. Checked in a workshop or demo.

**Scope.** in: principles of Capture, Inspect, Clarify, Implement and Recover · out: the steps inside each loop.

## Hierarchy

- **Parent:** [[FR-010-show-the-method]]
- **Children:** none.

> [!note] Open points
> The current dashboard page still explains only three loops; its content needs to catch up with this requirement.

## History

> Gernot Starke asked on 2026-11-11 to add the loops to the explanation. The five-loop scope was confirmed during the recovery report capture ([[SRC-056-closing-round-on-recovery-report]]). The current workflow definitions are [[capture]], [[inspect]], [[clarify]], [[implement]] and [[recover]].
