---
id: SOL-001
type: solution-strategy
title: Systems42 Dashboard
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-039-solution-strategy-of-the-dashboard]]", "[[SRC-040-grilling-session-on-the-solution-strategy]]"]
related: ["[[FR-029-the-dashboard-as-a-product]]", "[[FR-043-the-dashboard-checks-the-metamodel-version]]", "[[FR-044-sections-come-from-the-repositorys-metamodel]]", "[[FR-054-a-start-without-a-container-engine]]", "[[FR-055-an-installable-dashboard-app]]", "[[FR-056-a-public-website-for-the-dashboard]]", "[[FR-062-the-website-is-built-and-published-from-the-repository]]", "[[CC-001-tests-of-the-python-dashboard-are-plain-scripts]]"]
tags: [solution-strategy]
drivers: ["[[GOAL-001-trusted-answers]]", "[[GOAL-002-show-what-systems42-can-do]]", "[[GOAL-008-one-way-into-every-systems42-wiki]]", "[[QR-001-usable-on-phone-and-tablet]]", "[[QR-002-runs-alike-on-linux-and-macos]]", "[[QR-003-works-in-every-current-browser]]", "[[QR-004-the-wikis-content-stays-on-the-machine]]", "[[CON-001-proof-of-concept-not-production-ready]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]", "[[CON-005-the-dashboard-works-on-systems42-derivatives-only]]", "[[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]]", "[[CON-007-the-python-dashboard-is-the-reference-for-the-app]]"]
decisions: ["[[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]]", "[[DR-004-releases-are-container-images-pinned-per-wiki]]", "[[DR-005-the-dashboard-lives-in-its-own-repository]]", "[[DR-006-interactive-diagrams-are-projected-on-the-server-and-laid-out-in-the-browser]]", "[[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]"]
state: current
superseded-by:
---

# Systems42 Dashboard

> follows [[arc42]] (section 4)

## Strategy

- **Three ways to run it.** A start that is alike on every machine ([[QR-002-runs-alike-on-linux-and-macos]], [[GOAL-008-one-way-into-every-systems42-wiki]]) → a Flask application in a Docker image is the primary form, the same code runs with uv where no container engine runs, and an app needs nothing installed ([[CON-003-docker-is-the-supported-way-to-run-it]], [[CON-007-the-python-dashboard-is-the-reference-for-the-app]]). Each wiki names the release it runs. Decided in [[DR-004-releases-are-container-images-pinned-per-wiki]] and [[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]].
- **Separate from Systems42.** The method works without the dashboard ([[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]]), and the dashboard is the case study that shows the method at work ([[GOAL-002-show-what-systems42-can-do]]) → the dashboard has its own repository, with its requirements and its code. Decided in [[DR-005-the-dashboard-lives-in-its-own-repository]].
- **A public website.** People see the dashboard before they install it ([[GOAL-002-show-what-systems42-can-do]], [[FR-056-a-public-website-for-the-dashboard]]) → a Python script in the repository builds a static site with a demo, and GitHub Pages serves it ([[FR-062-the-website-is-built-and-published-from-the-repository]]).
- **Read-only, the wiki is the only data store.** [[CON-002-dashboard-never-writes-to-the-wiki]] → the dashboard has no database. It reads the Markdown files of the wiki and keeps what it derives in memory.
- **Everything shown is a projection.** Answers a reader can trust ([[GOAL-001-trusted-answers]]) and no writing ([[CON-002-dashboard-never-writes-to-the-wiki]]) → lists, matrices and diagrams are computed from the pages and their typed links on every load. Nothing drawn is stored.
- **The metamodel drives the dashboard.** [[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]], [[CON-005-the-dashboard-works-on-systems42-derivatives-only]] → the dashboard reads types, fields and allowed values from the wiki's metamodel and checks its version ([[FR-043-the-dashboard-checks-the-metamodel-version]], [[FR-044-sections-come-from-the-repositorys-metamodel]]). A project tailors names, brand and views in configuration files ([[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]]).
- **Pages are rendered on the server.** Every current browser, on phone and tablet too ([[QR-003-works-in-every-current-browser]], [[QR-001-usable-on-phone-and-tablet]]) → HTML comes from templates with little JavaScript, static diagrams are Mermaid, and every node of a diagram is also a link in a list. Only the interactive networks are laid out in the browser, decided in [[DR-006-interactive-diagrams-are-projected-on-the-server-and-laid-out-in-the-browser]].
- **Local and offline.** [[QR-004-the-wikis-content-stays-on-the-machine]] → the dashboard runs on the reader's machine, ships its script libraries and needs no account and no cloud service. It has no access control and is meant for a trusted network ([[CON-001-proof-of-concept-not-production-ready]]).
