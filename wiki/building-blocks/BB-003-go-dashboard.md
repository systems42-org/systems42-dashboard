---
id: BB-003
type: building-block
title: Go dashboard
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-044-building-blocks-of-the-systems42-dashboard]]", "[[SRC-045-grilling-session-on-context-and-building-blocks]]"]
related: ["[[SOL-002-three-ways-to-run-the-dashboard]]", "[[SOL-003-read-only-projections-over-markdown-files]]", "[[SOL-004-the-metamodel-drives-the-dashboard]]", "[[SOL-005-local-and-offline-execution]]"]
tags: [building-block]
parent: "[[CTX-001-systems42-dashboard-context]]"
drivers: ["[[GOAL-008-one-way-into-every-systems42-wiki]]", "[[FR-055-an-installable-dashboard-app]]", "[[FR-043-the-dashboard-checks-the-metamodel-version]]", "[[FR-044-sections-come-from-the-repositorys-metamodel]]", "[[FR-050-stop-the-dashboard-when-nobody-is-watching]]", "[[QR-001-usable-on-phone-and-tablet]]", "[[QR-003-works-in-every-current-browser]]", "[[QR-004-the-wikis-content-stays-on-the-machine]]", "[[CON-001-proof-of-concept-not-production-ready]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]", "[[CON-005-the-dashboard-works-on-systems42-derivatives-only]]", "[[CON-007-the-python-dashboard-is-the-reference-for-the-other-implementations]]"]
decisions: ["[[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]]", "[[DR-005-the-dashboard-lives-in-its-own-repository]]", "[[DR-006-interactive-diagrams-are-projected-on-the-server-and-laid-out-in-the-browser]]", "[[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]", "[[DR-009-pages-are-rendered-on-the-server-from-html-templates]]"]
uses: ["[[EIF-001-systems42-wiki]]"]
location: "_system/apps/dashboard/cmd/systems42-dashboard/, _system/apps/dashboard/internal/, _system/apps/dashboard/assets.go"
state: current
superseded-by:
---

# Go dashboard

> follows [[arc42]] (section 5, black box)

## Purpose / Responsibility

Second, standalone implementation of the dashboard in Go, compiled with `CGO_ENABLED=0` to a single static binary with embedded templates, static assets, brands and help text ([[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]], [[FR-055-an-installable-dashboard-app]]). It delivers route parity with [[BB-001-python-dashboard]] without Docker, uv or Python, serves as the embedded engine inside [[BB-004-macos-menu-bar-app]], and ships as unsupported static CLI binaries for Linux and Windows on each GitHub release.

## Interfaces

- **Provides:** The `systems42-dashboard` CLI (serving HTTP views and JSON APIs matching [[BB-001-python-dashboard]], plus `--check` and `--ready-json` lifecycle flags used by [[BB-004-macos-menu-bar-app]]).
- **Needs:** Read-only filesystem access to [[EIF-001-systems42-wiki]].

## Quality / Performance

Zero external runtime dependencies. Verified against [[BB-001-python-dashboard]] by automated route-parity tests (`tests/test_parity.py`) across multiple wikis. Where the two differ, the Python dashboard is the reference ([[CON-007-the-python-dashboard-is-the-reference-for-the-other-implementations]]).
