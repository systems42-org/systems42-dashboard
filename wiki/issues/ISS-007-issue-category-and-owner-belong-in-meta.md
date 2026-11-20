---
id: ISS-007
type: issue
title: Issue category and owner fields belong in meta
status: open
created: 2026-11-20
updated: 2026-11-20
sources: []
related: ["[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]", "[[FR-025-issue-list-with-filters]]", "[[FR-026-issues-carry-a-category]]", "[[FR-028-who-answers-an-issue]]"]
tags: [issue]
severity: minor
kind: gap
category: systems42
raised-by: Gernot Starke
owner: Gernot Starke and team
resolved: null
---

# Issue category and owner fields belong in meta

**What's unresolved.** This repository added `category:` and `owner:` to its local `_system/metamodel/types/type-issue.md` and `_templates/issue.md` (PR #11). Neither field exists in `systems42-org/meta` yet.

**Affects.** [[FR-025-issue-list-with-filters]], [[FR-026-issues-carry-a-category]] and [[FR-028-who-answers-an-issue]], which show and filter both fields. By [[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]] the issue schema belongs to Systems42 (`meta`), not to the dashboard.

**Context / evidence.**
- `category:` names one of six areas (`requirements`, `architecture`, `commons`, `content`, `orga`, `systems42`), independent of `kind:`.
- `owner:` names the person or stakeholder group expected to answer the issue, with no due dates.
- Syncing `_system/metamodel/` from `meta` (issue #33) would drop both fields until `meta` adopts them.
- Raised in Systems42 as [meta issue #53](https://github.com/systems42-org/meta/issues/53).

**Options.**
1. `meta` adopts `category:` and `owner:` in `type-issue.md` and `_templates/issue.md`.
2. `meta` leaves them out, and the dashboard shows them only on wikis that carry them.

**Resolution.**
