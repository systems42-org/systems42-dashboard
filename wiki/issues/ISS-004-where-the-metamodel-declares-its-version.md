---
id: ISS-004
type: issue
title: Where the metamodel declares its version
status: open
created: 2026-11-17
updated: 2026-11-21
sources: ["[[SRC-027-dashboard-distribution-and-metamodel-contract]]", "[[SRC-028-grilling-session-on-dashboard-distribution]]"]
related: ["[[FR-043-the-dashboard-checks-the-metamodel-version]]", "[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]"]
tags: [issue]
severity: minor
kind: gap
category: method
raised-by: "[[STK-012-maintainers]]"
owner: "[[STK-012-maintainers]]"
resolved: null
---

# Where the metamodel declares its version

**What's unresolved.** Systems42 has no stated place for the version of its metamodel. Gernot Starke proposes a file `_system/metamodel/metamodel-version.md`, because a file name should say what the file holds.

**Affects.** [[FR-043-the-dashboard-checks-the-metamodel-version]], which reads the version. By [[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]] the place is for Systems42 to decide.

**Context / evidence.**
- Today the version is `version: 0.1` in `_system/metamodel/meta-metamodel.md`, in meta, in this repository and in isaqb-atrium. No file `metamodel-version.md` exists.
- Which changes raise the version is not stated either.
- Raised in Systems42 as [meta issue #39](https://github.com/systems42-org/meta/issues/39).

**Options.**
1. A file `metamodel-version.md` in `_system/metamodel/`, with the version and what a version step means.
2. The version stays in `meta-metamodel.md`, and Systems42 states that this is the place.

**Resolution.**
