---
id: SOL-002
type: solution-strategy
title: Three ways to run the dashboard
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-039-solution-strategy-of-the-dashboard]]", "[[SRC-040-grilling-session-on-the-solution-strategy]]", "[[SRC-046-grilling-session-on-modularizing-the-solution-strategy]]", "[[SRC-049-grilling-session-on-the-mac-native-app]]"]
related: ["[[BB-001-python-dashboard]]", "[[BB-002-uv-cli-and-package-wrapper]]", "[[BB-003-go-dashboard]]", "[[BB-004-macos-menu-bar-app]]", "[[BB-005-wiki-launcher-and-make-facade]]", "[[FR-029-the-dashboard-as-a-product]]", "[[BB-007-mac-native-dashboard-app]]"]
tags: [solution-strategy]
drivers: ["[[GOAL-008-one-way-into-every-systems42-wiki]]", "[[QR-002-runs-alike-on-linux-and-macos]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[CON-007-the-python-dashboard-is-the-reference-for-the-other-implementations]]", "[[FR-042-start-a-pinned-release-with-one-command]]", "[[FR-054-a-start-without-a-container-engine]]", "[[FR-055-an-installable-dashboard-app]]"]
decisions: ["[[DR-004-releases-are-container-images-pinned-per-wiki]]", "[[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]"]
state: current
superseded-by:
---

# Three ways to run the dashboard

> follows [[arc42]] (section 4)

## Strategy

- **Same start on every machine** ([[GOAL-008-one-way-into-every-systems42-wiki]], [[QR-002-runs-alike-on-linux-and-macos]]) → a Flask application in a Docker image ([[BB-001-python-dashboard]]) is the primary form, pinned per wiki in `_system/wiki.yaml` and started by [[BB-005-wiki-launcher-and-make-facade]]. Decided in [[DR-004-releases-are-container-images-pinned-per-wiki]].
- **Run where no container engine starts** ([[FR-054-a-start-without-a-container-engine]], [[CON-003-docker-is-the-supported-way-to-run-it]]) → the same Python code ships as a release wheel wrapped for `uv` ([[BB-002-uv-cli-and-package-wrapper]]). Decided in [[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]].
- **Installable app with no terminal or Python** ([[FR-055-an-installable-dashboard-app]], [[CON-007-the-python-dashboard-is-the-reference-for-the-other-implementations]]) → a second standalone implementation in Go ([[BB-003-go-dashboard]]) powers the macOS menu-bar app ([[BB-004-macos-menu-bar-app]]). A third implementation in Swift is a second app that reads the wiki directly and shows it in its own window ([[FR-065-a-mac-native-dashboard-app]], [[BB-007-mac-native-dashboard-app]], planned). The Python dashboard stays the reference, and parity tests keep the implementations aligned. Decided in [[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]].
