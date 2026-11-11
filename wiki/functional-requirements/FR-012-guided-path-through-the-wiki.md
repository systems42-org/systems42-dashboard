---
id: FR-012
type: functional-requirement
title: Guided path through the wiki
status: draft
created: 2026-11-11
updated: 2026-11-11
sources: ["[[SRC-009-guided-path-through-the-wiki]]", "[[SRC-008-grilling-session-on-showing-the-method]]"]
related: ["[[FR-011-explain-the-three-loops]]", "[[STK-015-newcomers]]", "[[STK-008-workshop-participants]]", "[[STK-013-people-learning-or-presenting-systems42]]", "[[STK-022-prospective-adopters]]", "[[STK-023-keyholder]]"]
tags: ["functional-requirement", "method"]
stereotype: feature
parent: ["[[FR-010-show-the-method]]"]
priority: Should
release: unscheduled
lane: backbone
order: 12
goal: ["[[GOAL-002-show-what-systems42-can-do]]", "[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Guided path through the wiki

## Story

As a [[STK-015-newcomers]] **newcomer** I want **a guided path through the wiki, step by step**, so that **I understand what the system is about without knowing which page to open next**.

**PROBLEM / GOAL**

One path serves newcomers who read alone and presenters who walk it out loud.

- **Order.** Fixed by the method: vision, goals, stakeholders, scope and context, requirements, architecture, decisions, open issues, and finally how the wiki came about ([[FR-011-explain-the-three-loops]]).
- **Content.** Each step shows the wiki's own pages, so the path stays current without upkeep.
- **Empty and hidden steps.** A step with no pages is left out. So is a section the [[STK-023-keyholder|Keyholder]] has hidden in Configure.
- **Each step** shows one or two sentences on what the reader sees and why it matters, the same for every project. Example: "Goals: what the system should achieve, and how we measure it. Every requirement names the goal it serves."
- **Navigation.** Next and back, and the position, such as "step 3 of 8". A reader may leave the path to look around and comes back to the step they left.

**Success metric(s).** 4 of 5 test readers new to the wiki walk the whole path in 10 minutes or less. Afterwards they answer three questions: what is the system for, where are its requirements, where are its open questions. Checked in a workshop.

**Scope.** in: one path for all readers · out: separate paths per audience, and steps written by hand for one project.

## Hierarchy

- **Parent:** [[FR-010-show-the-method]]
- **Children:** none.

> [!note] Open points
> None.

## History

> Proposed by Claude on 2026-11-11 at Gernot Starke's request ([[SRC-009-guided-path-through-the-wiki]]). Shaped in fr-14 questions Q1 to Q4 of [[SRC-008-grilling-session-on-showing-the-method]]. Should, not Must: search carries GOAL-003's answers, and a Must would need its own epic under GOAL-003.
