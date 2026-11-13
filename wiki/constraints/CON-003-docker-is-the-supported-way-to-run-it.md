---
id: CON-003
type: constraint
title: Docker is the supported way to run the dashboard
status: draft
created: 2026-11-13
updated: 2026-11-13
sources: ["[[SRC-019-the-dashboard-as-a-product]]", "[[SRC-020-grilling-session-on-the-dashboard-as-a-product]]"]
related: ["[[FR-029-the-dashboard-as-a-product]]", "[[QR-002-runs-alike-on-linux-and-macos]]", "[[DR-004-releases-are-container-images-pinned-per-wiki]]", "[[STK-010-people-who-run-the-dashboard]]"]
tags: [constraint]
category: technical
---

# Docker is the supported way to run the dashboard

**Constraint.** The dashboard runs in Docker. Docker is the only thing a person needs to install for it. Linux and macOS are supported. Windows is left out for now.

**Rationale / origin.** One container image behaves the same on every machine, so a release looks and works the same everywhere ([[SRC-019-the-dashboard-as-a-product]]). Gernot Starke accepted Docker as a requirement for the product.

**Impact.**
- `./dashboard.sh local` runs the dashboard without Docker. It stays as a fallback for developers, without any promise that it works.
- The first start downloads the image and needs network. After that the dashboard runs offline. There is no installation from a file for now.
- Windows support comes back only when someone takes it up again.
