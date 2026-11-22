---
id: SOL-005
type: solution-strategy
title: Local and offline execution
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-039-solution-strategy-of-the-dashboard]]", "[[SRC-040-grilling-session-on-the-solution-strategy]]", "[[SRC-046-grilling-session-on-modularizing-the-solution-strategy]]"]
related: ["[[BB-001-python-dashboard]]", "[[BB-002-uv-cli-and-package-wrapper]]", "[[BB-003-go-dashboard]]", "[[BB-004-macos-menu-bar-app]]", "[[STK-020-data-protection-and-security-officers]]"]
tags: [solution-strategy]
drivers: ["[[QR-004-the-wikis-content-stays-on-the-machine]]", "[[CON-001-proof-of-concept-not-production-ready]]"]
decisions: []
state: current
superseded-by:
---

# Local and offline execution

> follows [[arc42]] (section 4)

## Strategy

- **Wiki content never leaves the machine** ([[QR-004-the-wikis-content-stays-on-the-machine]]) → every runtime (Docker, `uv`, Go binary and macOS app) runs locally on the reader's machine, ships all JavaScript libraries inside the artifact with no external CDNs, and requires no account, telemetry or cloud backend.
- **Trusted network, no access control** ([[CON-001-proof-of-concept-not-production-ready]]) → shared workshop sessions run directly over the local network without authentication, keeping setup to one command or click in a trusted room rather than building multi-user internet hosting.
