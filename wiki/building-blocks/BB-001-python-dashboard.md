---
id: BB-001
type: building-block
title: Python dashboard
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-044-building-blocks-of-the-systems42-dashboard]]", "[[SRC-045-grilling-session-on-context-and-building-blocks]]"]
related: ["[[SOL-002-three-ways-to-run-the-dashboard]]", "[[SOL-003-read-only-projections-over-markdown-files]]", "[[SOL-004-the-metamodel-drives-the-dashboard]]", "[[SOL-005-local-and-offline-execution]]", "[[CC-001-tests-of-the-python-dashboard-are-plain-scripts]]"]
tags: [building-block]
parent: "[[CTX-001-systems42-dashboard-context]]"
drivers: ["[[GOAL-001-trusted-answers]]", "[[GOAL-008-one-way-into-every-systems42-wiki]]", "[[FR-001-search-the-wiki]]", "[[FR-010-show-the-method]]", "[[FR-017-browse-by-area-and-section]]", "[[FR-024-see-what-is-still-open]]", "[[FR-029-the-dashboard-as-a-product]]", "[[FR-037-domain-terms]]", "[[FR-043-the-dashboard-checks-the-metamodel-version]]", "[[FR-044-sections-come-from-the-repositorys-metamodel]]", "[[FR-046-shared-session-in-a-workshop]]", "[[QR-001-usable-on-phone-and-tablet]]", "[[QR-002-runs-alike-on-linux-and-macos]]", "[[QR-003-works-in-every-current-browser]]", "[[QR-004-the-wikis-content-stays-on-the-machine]]", "[[CON-001-proof-of-concept-not-production-ready]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]", "[[CON-005-the-dashboard-works-on-systems42-derivatives-only]]", "[[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]]", "[[CON-007-the-python-dashboard-is-the-reference-for-the-app]]"]
decisions: ["[[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]]", "[[DR-004-releases-are-container-images-pinned-per-wiki]]", "[[DR-005-the-dashboard-lives-in-its-own-repository]]", "[[DR-006-interactive-diagrams-are-projected-on-the-server-and-laid-out-in-the-browser]]", "[[DR-009-pages-are-rendered-on-the-server-from-html-templates]]"]
uses: ["[[EIF-001-systems42-wiki]]"]
location: _system/apps/dashboard/
state: current
superseded-by:
---

# Python dashboard

> follows [[arc42]] (section 5, black box)

## Purpose / Responsibility

Reference Flask web application served with Gunicorn inside the primary Docker container image ([[DR-004-releases-are-container-images-pinned-per-wiki]], [[CON-003-docker-is-the-supported-way-to-run-it]]). It reads a Systems42 wiki and its metamodel, projects all lists, matrices, story maps and diagrams on demand, indexes full-text search, manages in-memory workshop sessions and serves HTML and JSON to the browser. Every new feature is implemented here first, and parity checks test other implementations against it ([[CON-007-the-python-dashboard-is-the-reference-for-the-app]]).

## Interfaces

- **Provides:** HTTP web UI and JSON endpoints (search, session presence, interactive graph data) on port 8000 inside the container (mapped to `DASH_PORT`, default 8080, on the host), plus the shared Flask application imported by [[BB-002-uv-cli-and-package-wrapper]] and [[BB-006-public-website-builder]].
- **Needs:** Read-only filesystem access to [[EIF-001-systems42-wiki]] (mounted at `/repo:ro` in Docker or configured via `REPO_DIR`).

## Quality / Performance

Runs identically on Linux and macOS inside the pinned container image ([[QR-002-runs-alike-on-linux-and-macos]]), ships all JavaScript libraries locally so no wiki content leaves the machine ([[QR-004-the-wikis-content-stays-on-the-machine]]), and provides a text equivalent beside every diagram ([[QR-001-usable-on-phone-and-tablet]]). Tested by standalone Python scripts run in Docker ([[CC-001-tests-of-the-python-dashboard-are-plain-scripts]]).
