---
id: BB-004
type: building-block
title: macOS menu-bar app
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-044-building-blocks-of-the-systems42-dashboard]]", "[[SRC-045-grilling-session-on-context-and-building-blocks]]", "[[SRC-049-grilling-session-on-the-mac-native-app]]"]
related: ["[[FR-064-install-the-app-with-homebrew]]", "[[SOL-002-three-ways-to-run-the-dashboard]]", "[[SOL-005-local-and-offline-execution]]", "[[BB-007-mac-native-dashboard-app]]"]
tags: [building-block]
parent: "[[CTX-001-systems42-dashboard-context]]"
drivers: ["[[GOAL-008-one-way-into-every-systems42-wiki]]", "[[FR-055-an-installable-dashboard-app]]", "[[QR-004-the-wikis-content-stays-on-the-machine]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[CON-005-the-dashboard-works-on-systems42-derivatives-only]]"]
decisions: ["[[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]"]
uses: ["[[BB-003-go-dashboard]]"]
location: _system/apps/dashboard/macos/
state: current
superseded-by:
---

# macOS menu-bar app

> follows [[arc42]] (section 5, black box)

## Purpose / Responsibility

Swift and AppKit menu-bar application (`Systems42 Dashboard.app`, packaged as a universal `arm64` and `x86_64` `.dmg`) that lets macOS users open any Systems42 wiki without Docker, uv or a terminal ([[FR-055-an-installable-dashboard-app]]). It validates selected folders, stores a local list of recent wikis, starts and stops one embedded [[BB-003-go-dashboard]] process per open wiki and opens the dashboard URL in the default browser. Future extension: an install with Homebrew ([[FR-064-install-the-app-with-homebrew]]).

## Interfaces

- **Provides:** macOS menu-bar UI (Open Wiki, Recent Wikis, running wiki controls and Quit) and Finder-installable `.dmg` on each GitHub release.
- **Needs:** Embedded universal binary of [[BB-003-go-dashboard]] (invoked with `--check` and `--ready-json`) and macOS 14.0 or later.

## Quality / Performance

Runs fully offline on macOS with no container engine or Python runtime required ([[QR-004-the-wikis-content-stays-on-the-machine]]). Releases are currently ad-hoc signed, so first-time users remove the macOS quarantine attribute or download with `curl` until Apple Developer ID signing and notarization are enabled.

## Open issues

- Signing and notarization with an Apple Developer ID certificate is not yet active on releases ([[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]).
- This app keeps showing pages in the default browser. An app with its own window is [[BB-007-mac-native-dashboard-app]] ([[SRC-049-grilling-session-on-the-mac-native-app]]).
