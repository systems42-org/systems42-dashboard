---
id: ISS-003
type: issue
title: The goal coverage projection cites decisions from another wiki
status: open
created: 2026-11-13
updated: 2026-11-14
sources: ["[[SRC-024-grilling-session-on-the-goal-coverage-matrix]]"]
related: ["[[FR-036-goal-coverage-matrix]]", "[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]"]
tags: [issue]
severity: minor
kind: contradiction
category: systems42
raised-by: Claude
owner: Gernot Starke and team
resolved: null
---

# The goal coverage projection cites decisions from another wiki

**What's unresolved.** Systems42's projection `proj-goal-coverage` (`_system/metamodel/projections/proj-goal-coverage.md`) names `decision: DR-018-projections-from-typed-edges` and cites DR-011 in its text. Both decision records exist only in isaqb-atrium. In this wiki, DR-011 and DR-018 do not exist, and the numbers are taken by nothing or by other decisions later.

**Affects.** [[FR-036-goal-coverage-matrix]], which shows this projection. By [[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]] the fix belongs to Systems42, not to the dashboard.

**Context / evidence.**
- The metamodel says a `decision` reference names a full stem because "projects number their own decisions". A project created from Systems42 still inherits references to decisions it does not have.
- Its field `implemented: "/goals (covering-epic counts)"` also describes an older state of the dashboard.
- Its text says "an objective no epic serves is a gap". Gernot Starke decided on 2026-11-14 that a goal at least one feature serves is not a gap ([[FR-036-goal-coverage-matrix]]). The projection should say so.
- Raised in Systems42 as [meta issue #37](https://github.com/systems42-org/meta/issues/37), covering all three points.

**Options.**
1. The metamodel cites Systems42's own decisions (in `systems42-org/meta`) by a stable name or link, never a project's DR number.
2. Each project rewrites the references when it syncs the method.

**Resolution.**
