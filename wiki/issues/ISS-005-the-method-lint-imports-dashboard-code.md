---
id: ISS-005
type: issue
title: The method's lint imports dashboard code
status: open
created: 2026-11-17
updated: 2026-11-21
sources: ["[[SRC-027-dashboard-distribution-and-metamodel-contract]]", "[[SRC-028-grilling-session-on-dashboard-distribution]]"]
related: ["[[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]]", "[[DR-005-the-dashboard-lives-in-its-own-repository]]", "[[FR-044-sections-come-from-the-repositorys-metamodel]]"]
tags: [issue]
severity: major
kind: contradiction
category: method
raised-by: Claude
owner: "[[STK-012-maintainers]]"
resolved: null
---

# The method's lint imports dashboard code

**What's unresolved.** `_system/scripts/metamodel-lint.py`, a script of the Systems42 method, imports the dashboard's `catalog.py` and fails without it. That contradicts [[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]].

**Affects.** [[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]] and [[DR-005-the-dashboard-lives-in-its-own-repository]]: a wiki without dashboard code fails the lint.

**Context / evidence.**
- The lint compares `catalog.SECTIONS` with the framework blocks (line 208 in this repository's copy).
- Same cause in meta: `new-project.sh` still mirrors `_system/apps` into every project, and meta holds an older copy of the dashboard code.
- Once [[FR-044-sections-come-from-the-repositorys-metamodel]] is built, the check has nothing left to compare.
- Raised in Systems42 as [meta issue #40](https://github.com/systems42-org/meta/issues/40).

**Options.**
1. Systems42 removes the import and the check from the lint.
2. The check moves into the dashboard's own tests until FR-044 is built.

**Resolution.**
