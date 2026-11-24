---
id: FR-068
type: functional-requirement
title: Read the metamodel as a reference
status: draft
created: 2026-11-24
updated: 2026-11-24
sources: ["[[SRC-055-recovery-report-systems42-dashboard]]"]
related: ["[[STK-013-people-learning-or-presenting-systems42]]", "[[STK-001-readers]]", "[[FR-010-show-the-method]]", "[[FR-035-method-terms-lead-to-their-definition]]", "[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]", "[[BB-001-python-dashboard]]"]
tags: [functional-requirement, method]
notation: agile
level: feature
parent: ["[[FR-010-show-the-method]]"]
building-blocks: ["[[BB-001-python-dashboard]]"]
priority: Should
release: unscheduled
lane: backbone
order: 68
goal: ["[[GOAL-002-show-what-systems42-can-do]]", "[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Read the metamodel as a reference

## Story

As a [[STK-013-people-learning-or-presenting-systems42|person learning Systems42]] I want to read the full metamodel with definitions and examples, so that I understand how a Systems42 wiki is structured.

**PROBLEM / GOAL**

The reference covers the metamodel's page types, relations, framework sections, projections and rules. It links each construct to a live example from the wiki. Systems42 defines the metamodel; the dashboard presents it ([[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]).

**Success metric(s).** Every construct in the metamodel appears in the reference with its definition and fields. Each construct with an example links to a matching page in the wiki.

**Scope.** in: reading the whole metamodel as a reference · out: defining or changing the metamodel.

## Hierarchy

- **Parent:** [[FR-010-show-the-method]]
- **Children:** none.

## History

> The recovery report found a metamodel reference in the code but noted that [[FR-035-method-terms-lead-to-their-definition]] covers only anchor entries. The human wants the full reference for learning and explaining the method ([[SRC-055-recovery-report-systems42-dashboard]]).
