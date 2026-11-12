---
id: FR-018
type: functional-requirement
title: Orientation on the first page
status: draft
created: 2026-11-12
updated: 2026-11-12
sources: ["[[SRC-013-browse-by-area-and-section]]", "[[SRC-014-grilling-session-on-browsing]]"]
related: ["[[FR-012-guided-path-through-the-wiki]]", "[[GOAL-001-trusted-answers]]"]
tags: ["functional-requirement", "navigation"]
stereotype: feature
parent: ["[[FR-017-browse-by-area-and-section]]"]
priority: Must
release: unscheduled
lane: backbone
order: 18
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]", "[[GOAL-007-readers-who-come-back]]"]
---

# Orientation on the first page

## Story

As a [[STK-015-newcomers]] **newcomer** I want **the first page to tell me what this wiki is about and where to go**, so that **I start in the right place**. As a returning reader I want **to see what changed**, so that **I keep up without searching**.

**PROBLEM / GOAL**

The first page shows, from top to bottom:

1. **What this is.** The system's name and its vision in one sentence ([[GOAL-001-trusted-answers]]).
2. **Start the guided path.** One link for newcomers ([[FR-012-guided-path-through-the-wiki]]).
3. **The areas.** Requirements, Architecture and Commons, each with its sections and their page counts ([[FR-019-section-at-a-glance]]).
4. **The center tile**, in the middle of the areas:
   - the last 3 to 4 changes to the wiki, with a link to the **changes page**, which lists all changes to the wiki (not the dashboard's own `CHANGELOG.md`);
   - the open questions: how many issues are open, and the most important ones by name.

The center tile shows no page count, because the section tiles carry it.

**Success metric(s).** On a test wiki, the first page shows the vision sentence, the guided path link, the three areas, the latest changes with a working link to the changes page, and the open issue count. A change to a page appears among the latest changes after a reload.

**Scope.** in: the first page and the changes page · out: completeness or maturity figures for the whole wiki.

## Hierarchy

- **Parent:** [[FR-017-browse-by-area-and-section]]
- **Children:** none.

> [!note] Open points
> None.

## History

> Shaped in Q3 and Q4 of [[SRC-014-grilling-session-on-browsing]]. Gernot Starke moved changes and open questions into the center tile and dropped the page count there.
