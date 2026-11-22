---
id: FR-065
type: functional-requirement
title: A Mac-native dashboard app
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-049-grilling-session-on-the-mac-native-app]]"]
related: ["[[FR-055-an-installable-dashboard-app]]", "[[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]", "[[CON-007-the-python-dashboard-is-the-reference-for-the-other-implementations]]", "[[BB-007-mac-native-dashboard-app]]", "[[FR-043-the-dashboard-checks-the-metamodel-version]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[CON-005-the-dashboard-works-on-systems42-derivatives-only]]", "[[FR-046-shared-session-in-a-workshop]]", "[[QR-001-usable-on-phone-and-tablet]]", "[[QR-003-works-in-every-current-browser]]"]
tags: ["functional-requirement", "product"]
notation: agile
level: feature
parent: ["[[FR-029-the-dashboard-as-a-product]]"]
priority: Should
release: unscheduled
lane: backbone
order: 65
goal: ["[[GOAL-008-one-way-into-every-systems42-wiki]]"]
---

# A Mac-native dashboard app

## Story

As a [[STK-001-readers|requirements engineer]] who works on the wiki on a Mac I want **the dashboard as a Mac-native app that reads the wiki folder directly**, so that **I see every saved change at once and work in windows, menus and shortcuts as in any Mac app**.

**PROBLEM / GOAL**

- **Why.** People and AI agents write pages while the dashboard is open. The browser dashboards show a change after a reload. The app follows the files.
- **A Mac app.** One window per wiki with sidebar, list and page, a menu bar and keyboard shortcuts. No browser and no local server.
- **A third implementation.** The app is written in Swift, next to the Python and the Go dashboard ([[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]). The three are equal products. For what a page shows, the Python dashboard is the reference ([[CON-007-the-python-dashboard-is-the-reference-for-the-other-implementations]]).
- **Next to the installable app.** [[FR-055-an-installable-dashboard-app]] stays. Both apps can be installed on one Mac.
- **One app for every wiki.** As in FR-055: installed once, it shows any Systems42 wiki, names a differing `dashboard_version:` and shows the wiki anyway. It checks the metamodel version ([[FR-043-the-dashboard-checks-the-metamodel-version]]).
- **Read only.** The app writes nothing to the wiki ([[CON-002-dashboard-never-writes-to-the-wiki]]) and shows Systems42 derivatives only ([[CON-005-the-dashboard-works-on-systems42-derivatives-only]]).

**Success metric(s).** On a Mac without Docker, uv, Python and Go, a person opens a Systems42 wiki with the app. Every page shows the same title, status, links and open issues as the Python dashboard of the same release, and every section the same pages. A page saved in an editor shows its new text within 2 seconds, without a click.

**Scope.**
- in: the pages, lists, search and projections of the dashboard · several wikis open at once · opening a page in Obsidian or in Finder · links that name a page.
- out: the shared session, the connection dot and the stop when nobody is watching ([[FR-046-shared-session-in-a-workshop]], one Mac has one reader) · the launcher and a pinned release per wiki · the intro of a brand · phones, tablets and browsers ([[QR-001-usable-on-phone-and-tablet]] and [[QR-003-works-in-every-current-browser]] do not apply) · Windows.

## Hierarchy

- **Parent:** [[FR-029-the-dashboard-as-a-product]]
- **Children:** none.

> [!note] Open points
> - The graph diagrams are drawn in a web view inside the app for now. Gernot Starke looks at this again once a prototype runs.
> - The plan is [issue #112](https://github.com/systems42-org/systems42-dashboard/issues/112).

## History

> Asked for by Gernot Starke on 2026-11-22. He chose the window layout with three columns from three sketches, the readers, the metric and the priority ([[SRC-049-grilling-session-on-the-mac-native-app]]). The role requirements engineer is Claude's choice.
