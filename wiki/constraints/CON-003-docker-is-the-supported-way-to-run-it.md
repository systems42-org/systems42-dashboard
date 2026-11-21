---
id: CON-003
type: constraint
title: Docker and uv are the supported ways to run the dashboard
status: draft
created: 2026-11-13
updated: 2026-11-20
sources: ["[[SRC-019-the-dashboard-as-a-product]]", "[[SRC-020-grilling-session-on-the-dashboard-as-a-product]]", "[[SRC-027-dashboard-distribution-and-metamodel-contract]]", "[[SRC-028-grilling-session-on-dashboard-distribution]]", "[[SRC-036-grilling-session-on-running-without-a-container-engine]]"]
related: ["[[FR-029-the-dashboard-as-a-product]]", "[[QR-002-runs-alike-on-linux-and-macos]]", "[[DR-004-releases-are-container-images-pinned-per-wiki]]", "[[STK-010-operators]]", "[[ISS-006-other-container-engines-than-docker]]", "[[FR-054-a-start-without-a-container-engine]]", "[[FR-055-an-installable-dashboard-app]]", "[[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]"]
tags: [constraint]
category: technical
---

# Docker and uv are the supported ways to run the dashboard

**Constraint.** The dashboard runs in Docker, or with uv where no container engine runs ([[FR-054-a-start-without-a-container-engine]]). Docker or uv is the only thing a person needs to install for it. Linux and macOS are supported. Windows is left out for now.

**Rationale / origin.** One container image behaves the same on every machine, so a release looks and works the same everywhere ([[SRC-019-the-dashboard-as-a-product]]). Gernot Starke accepted Docker as a requirement for the product. On 2026-11-20 he added uv, because inside a virtual machine no container engine starts ([[SRC-036-grilling-session-on-running-without-a-container-engine]], [[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]).

**Impact.**
- `./dashboard.sh uv` runs the code and the server of the image, and the tests cover it.
- `./dashboard.sh local` also runs the dashboard without Docker. It stays as a fallback for developers, without any promise that it works.
- The first start downloads the image or the package and needs network. After that the dashboard runs offline. There is no installation from a file for now.
- Windows support comes back only when someone takes it up again.
- An installable app for macOS is planned ([[FR-055-an-installable-dashboard-app]]).
- Other container engines such as Podman are not supported for now ([[ISS-006-other-container-engines-than-docker]]).
