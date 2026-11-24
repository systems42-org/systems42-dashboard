---
id: FR-067
type: functional-requirement
title: Read the project About page
status: draft
created: 2026-11-24
updated: 2026-11-24
sources: ["[[SRC-055-recovery-report-systems42-dashboard]]"]
related: ["[[STK-001-readers]]", "[[BB-001-python-dashboard]]", "[[FR-017-browse-by-area-and-section]]"]
tags: [functional-requirement]
notation: agile
level: feature
parent: ["[[FR-017-browse-by-area-and-section]]"]
building-blocks: ["[[BB-001-python-dashboard]]"]
priority: Should
release: unscheduled
lane: backbone
order: 67
goal: ["[[GOAL-002-show-what-systems42-can-do]]"]
---

# Read the project About page

## Story

As a [[STK-001-readers|reader]] I want to read the project's About page and the files it links, so that I understand the project's name, brand and purpose.

**PROBLEM / GOAL**

The dashboard can show project documentation that introduces the wiki it serves. The page and its linked files come from the project repository.

**Success metric(s).** When the wiki names an About page, a reader can open it and its local linked files from the dashboard. When no About page is configured, the dashboard does not show a broken link.

**Scope.** in: reading the project About page and its linked files · out: editing project documentation or showing files outside the project documentation.

## Hierarchy

- **Parent:** [[FR-017-browse-by-area-and-section]]
- **Children:** none.

## History

> The recovery report found this capability in the code at revision `8b98d1a`. The human wants it to explain the brand and project to readers ([[SRC-055-recovery-report-systems42-dashboard]]).
