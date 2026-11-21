---
id: ISS-008
type: issue
title: Q42 dimensions for quality requirements belong in meta
status: open
created: 2026-11-20
updated: 2026-11-20
sources: []
related: ["[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]", "[[DR-003-quality-requirements-are-classified-by-q42-dimensions]]", "[[QR-001-usable-on-phone-and-tablet]]", "[[QR-002-runs-alike-on-linux-and-macos]]", "[[QR-003-works-in-every-current-browser]]"]
tags: [issue]
severity: major
kind: contradiction
category: systems42
raised-by: Gernot Starke
owner: Gernot Starke and team
resolved: null
---

# Q42 dimensions for quality requirements belong in meta

**What's unresolved.** This repository replaced ISO 25010 `attribute:` with multi-value Q42 `dimensions:` in its local `_system/metamodel/types/type-quality-requirement.md` and `_templates/quality-requirement.md` ([[DR-003-quality-requirements-are-classified-by-q42-dimensions]]). `systems42-org/meta` still declares single-value `attribute:`.

**Affects.** [[DR-003-quality-requirements-are-classified-by-q42-dimensions]], [[QR-001-usable-on-phone-and-tablet]], [[QR-002-runs-alike-on-linux-and-macos]] and [[QR-003-works-in-every-current-browser]]. By [[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]], `meta` leads on the metamodel.

**Context / evidence.**
- Tracked in Systems42 as [meta issue #35](https://github.com/systems42-org/meta/issues/35).
- On 2026-11-20 Gernot Starke confirmed that `meta` leads on QR classification and deprecated local `DR-003`.
- Syncing `_system/metamodel/` from `meta` (issue #33) would overwrite `dimensions:` back to `attribute:` until `meta#35` lands.

**Options.**
1. `meta` adopts Q42 `dimensions:` in `type-quality-requirement.md` and closes `meta#35`.
2. `meta` keeps `attribute:` or adopts another classification, and this wiki and the dashboard follow `meta`.

**Resolution.**
