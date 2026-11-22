---
id: BB-007
type: building-block
title: Mac-native dashboard app
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-049-grilling-session-on-the-mac-native-app]]"]
related: ["[[SOL-002-three-ways-to-run-the-dashboard]]", "[[BB-004-macos-menu-bar-app]]", "[[BB-003-go-dashboard]]"]
tags: [building-block]
parent: "[[CTX-001-systems42-dashboard-context]]"
drivers: ["[[GOAL-008-one-way-into-every-systems42-wiki]]", "[[FR-065-a-mac-native-dashboard-app]]", "[[QR-004-the-wikis-content-stays-on-the-machine]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[CON-005-the-dashboard-works-on-systems42-derivatives-only]]", "[[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]]", "[[CON-007-the-python-dashboard-is-the-reference-for-the-other-implementations]]"]
decisions: ["[[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]"]
uses: ["[[EIF-001-systems42-wiki]]"]
location: _system/apps/dashboard-mac/
state: planned
superseded-by:
---

# Mac-native dashboard app

> follows [[arc42]] (section 5, black box)

## Purpose / Responsibility

Third implementation of the dashboard, in Swift and SwiftUI ([[FR-065-a-mac-native-dashboard-app]]). It reads the wiki folder directly and shows it in one window per wiki, with sidebar, list and page. It starts no server and uses none of the other building blocks.

## Interfaces

- **Provides:** a macOS app with windows, a menu bar and `systems42://` links to pages.
- **Needs:** read access to the wiki folder the person chooses ([[EIF-001-systems42-wiki]]) and macOS 14.0 or later.

## Quality / Performance

Runs in the App Sandbox with read-only access to the chosen folder, so the system enforces [[CON-002-dashboard-never-writes-to-the-wiki]]. It opens no network connection ([[QR-004-the-wikis-content-stays-on-the-machine]]). A saved page shows within 2 seconds.

## Open issues

- Its pages are checked against data taken from [[BB-003-go-dashboard]], not against rendered pages, because it produces no HTML.
- The graph diagrams are drawn in a web view inside the app for now.
