---
id: ISS-009
type: issue
title: Correct ambiguous and unresolved code references
status: open
created: 2026-11-24
updated: 2026-11-24
sources: ["[[SRC-055-recovery-report-systems42-dashboard]]"]
related: ["[[STK-012-maintainers]]", "[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]", "[[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]]", "[[FR-035-method-terms-lead-to-their-definition]]"]
tags: [issue]
severity: minor
kind: gap
category: method
raised-by: agent
owner: "[[STK-012-maintainers]]"
resolved: null
---

# Correct ambiguous and unresolved code references

**What's unresolved.** References in the dashboard code and documentation mix this project's requirement IDs with upstream Systems42 decision IDs. Some IDs point to a different local requirement, some name a decision that exists only in another repository, and some do not resolve anywhere in this wiki.

**Affects.** Maintainers who use source references to trace behavior back to a requirement or decision, including [[FR-035-method-terms-lead-to-their-definition]] and the metamodel boundary in [[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]].

**Context / evidence.** The report at revision `8b98d1a` lists mismatched, foreign and dangling IDs ([[SRC-055-recovery-report-systems42-dashboard]]). The current code still uses [[FR-004-question-style-queries|FR-004]] for the default requirement notation in `_system/apps/dashboard/app.py` and [[FR-023-areas-and-sections-follow-the-tailoring|FR-023]] for project notations in `_system/apps/dashboard/metamodel.py`; those IDs mean different things in this wiki. Code and template comments also use upstream decision numbers without a repository-qualified link, while this wiki has decision pages only through [[DR-009-pages-are-rendered-on-the-server-from-html-templates|DR-009]].

**Options.**
1. Correct the local IDs and qualify upstream references in the next dashboard change; remove or replace references that no longer resolve. This keeps code trace claims reviewable.
2. Leave the references as they are. This saves a small documentation change but keeps the ambiguity.

**Resolution.** The human chose option 1 in the report's closing round. The issue remains open until the current references are corrected.
