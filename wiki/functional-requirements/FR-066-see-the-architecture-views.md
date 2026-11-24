---
id: FR-066
type: functional-requirement
title: See the architecture views
status: draft
created: 2026-11-24
updated: 2026-11-24
sources: ["[[SRC-055-recovery-report-systems42-dashboard]]"]
related: ["[[STK-001-readers]]", "[[STK-012-maintainers]]", "[[CTX-001-systems42-dashboard-context]]", "[[BB-001-python-dashboard]]", "[[FR-047-see-the-requirements-as-a-story-map]]"]
tags: [functional-requirement, architecture]
notation: agile
level: feature
parent: ["[[FR-017-browse-by-area-and-section]]"]
building-blocks: ["[[BB-001-python-dashboard]]"]
priority: Must
release: unscheduled
lane: backbone
order: 66
goal: ["[[GOAL-005-architecture-traced-to-requirements]]"]
---

# See the architecture views

## Story

As a [[STK-001-readers|software architect]] I want to see the system context, building blocks, crosscutting concepts, runtime scenarios and deployment, so that I can understand how the solution fits together. [[STK-012-maintainers]] use the same views to explain and maintain it.

**PROBLEM / GOAL**

The dashboard shows five architecture views projected from the wiki: context, building blocks, crosscutting concepts, runtime scenarios and deployment. The views link their elements to the pages that define them.

**Success metric(s).** On a test wiki with at least one page for each architecture type, all five views are available, each page appears in its view, and each diagram element links to its page.

**Scope.** in: the five views and links to their source pages · out: editing architecture pages or diagrams in the dashboard.

## Hierarchy

- **Parent:** [[FR-017-browse-by-area-and-section]]
- **Children:** none.

## History

> The recovery report found these views in the code at revision `8b98d1a`. The human confirmed they are required ([[SRC-055-recovery-report-systems42-dashboard]]).
