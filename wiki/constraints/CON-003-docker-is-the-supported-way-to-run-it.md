---
id: CON-003
type: constraint
title: The dashboard runs in Docker, with uv, or as an app
status: draft
created: 2026-11-13
updated: 2026-11-22
sources: ["[[SRC-019-the-dashboard-as-a-product]]", "[[SRC-020-grilling-session-on-the-dashboard-as-a-product]]", "[[SRC-027-dashboard-distribution-and-metamodel-contract]]", "[[SRC-028-grilling-session-on-dashboard-distribution]]", "[[SRC-036-grilling-session-on-running-without-a-container-engine]]", "[[SRC-039-solution-strategy-of-the-dashboard]]", "[[SRC-040-grilling-session-on-the-solution-strategy]]"]
related: ["[[FR-029-the-dashboard-as-a-product]]", "[[QR-002-runs-alike-on-linux-and-macos]]", "[[DR-004-releases-are-container-images-pinned-per-wiki]]", "[[STK-010-operators]]", "[[ISS-006-other-container-engines-than-docker]]", "[[FR-054-a-start-without-a-container-engine]]", "[[FR-055-an-installable-dashboard-app]]", "[[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]", "[[CON-007-the-python-dashboard-is-the-reference-for-the-app]]", "[[SOL-001-systems42-dashboard]]"]
tags: [constraint]
category: technical
---

# The dashboard runs in Docker, with uv, or as an app

**Constraint.** A person installs one thing to run the dashboard: Docker, uv or the app. Docker is the primary form. Docker and uv run on Linux and macOS. The app runs on macOS. Windows is not supported. The only supported container engine is Docker.

**Rationale / origin.** One container image behaves the same on every machine, so a release looks and works the same everywhere ([[SRC-019-the-dashboard-as-a-product]]). Gernot Starke accepted Docker as a requirement for the product. On 2026-11-20 he added uv and the app, because inside a virtual machine no container engine starts ([[SRC-036-grilling-session-on-running-without-a-container-engine]], [[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]). On 2026-11-22 he confirmed Docker as the primary form ([[SRC-040-grilling-session-on-the-solution-strategy]]).

**Impact.**
- `./dashboard.sh uv` runs the code and the server of the image, and the tests cover it ([[FR-054-a-start-without-a-container-engine]]).
- The app is a second implementation that shows the same pages ([[FR-055-an-installable-dashboard-app]], [[CON-007-the-python-dashboard-is-the-reference-for-the-app]]).
- `./dashboard.sh local` also runs the dashboard without Docker. It is a fallback for developers, without any promise that it works.
- The first start with Docker or uv downloads the image or the package and needs network. After that the dashboard runs offline. There is no installation from a file.
- Whether another container engine such as Podman is supported is open in [[ISS-006-other-container-engines-than-docker]].
