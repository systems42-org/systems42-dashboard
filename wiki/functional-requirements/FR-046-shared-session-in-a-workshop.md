---
id: FR-046
type: functional-requirement
title: Shared session in a workshop
status: draft
created: 2026-11-19
updated: 2026-11-19
sources: ["[[SRC-032-shared-session-in-a-workshop]]", "[[SRC-033-grilling-session-on-the-shared-session]]"]
related: ["[[STK-023-keyholder]]", "[[STK-007-workshop-facilitators]]", "[[STK-008-workshop-participants]]", "[[STK-013-people-learning-or-presenting-systems42]]", "[[FR-015-read-the-formalities-in-the-footer]]", "[[FR-023-areas-and-sections-follow-the-tailoring]]", "[[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[CON-001-proof-of-concept-not-production-ready]]"]
tags: ["functional-requirement", "method"]
stereotype: feature
parent: ["[[FR-010-show-the-method]]"]
priority: Should
release: unscheduled
lane: backbone
order: 46
goal: ["[[GOAL-002-show-what-systems42-can-do]]"]
---

# Shared session in a workshop

## Story

As a [[STK-007-workshop-facilitators|workshop facilitator]] I want **the group to open the same dashboard on their own devices, while one person decides what the group sees**, so that **everyone looks at the same wiki during the workshop**.

**PROBLEM / GOAL**

- **Join.** The home page shows a QR code and its address. `/join` shows the code full size for projecting.
- **Who is connected.** Every page shows how many browser tabs are connected ([[FR-015-read-the-formalities-in-the-footer]]). `/who` lists them under generated nicknames, never real names.
- **Keyholder.** The first tab to connect holds the rights ([[STK-023-keyholder]]) and is called "Yoda". When that tab closes, the rights pass to the tab that connected next-earliest. That tab keeps its own nickname. The rights never go back to an earlier holder.
- **View.** A dialog called View shows everyone which areas and sections are shown. Only the Keyholder changes it. A hidden section leaves the home page, the area pages and the top bar, but stays reachable by address and search.
- The view offers only what the tailoring includes ([[FR-023-areas-and-sections-follow-the-tailoring]], [[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]]).
- The view lasts until the dashboard stops. After a restart the dashboard shows everything the project uses. It writes no file for the view ([[CON-002-dashboard-never-writes-to-the-wiki]]).
- **End.** Only the Keyholder sees "Disconnect all", which ends the session for everyone. The dashboard stops itself a few seconds after the last tab closes ([[FR-050-stop-the-dashboard-when-nobody-is-watching]]).
- **Reload.** Anyone can make the dashboard read the wiki from disk again.

**Success metric(s).** Three devices join by the QR code. After the Keyholder hides a section and the others reload, the section is gone from the home page on all three. The wiki's repository holds no changed file.

**Scope.** in: joining, the list of connected tabs, the Keyholder's rights, the view, ending the session · out: a login and real names ([[CON-001-proof-of-concept-not-production-ready]]), the tailoring.

## Hierarchy

- **Parent:** [[FR-010-show-the-method]]
- **Children:** [[FR-050-stop-the-dashboard-when-nobody-is-watching]]

> [!note] Open points
> - Not built yet: the dialog is still called Configure and saves the view in `_system/dashboard.yaml`. All other points are built.
> - The success metric is a proposal by Claude. Nobody has agreed it yet.

## History

> Extracted from the dashboard code on 2026-11-10 ([[SRC-032-shared-session-in-a-workshop]]). Gernot Starke decided on 2026-11-19: one feature, Should, the view lasts until the dashboard stops, the dialog is called View, and the nickname "Yoda" stays with the first holder ([[SRC-033-grilling-session-on-the-shared-session]]).
