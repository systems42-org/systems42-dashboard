---
id: CON-006
type: constraint
title: The dashboard depends on the metamodel, never the reverse
status: draft
created: 2026-11-17
updated: 2026-11-24
sources: ["[[SRC-027-dashboard-distribution-and-metamodel-contract]]", "[[SRC-028-grilling-session-on-dashboard-distribution]]", "[[SRC-055-recovery-report-systems42-dashboard]]"]
related: ["[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]", "[[FR-044-sections-come-from-the-repositorys-metamodel]]", "[[FR-043-the-dashboard-checks-the-metamodel-version]]", "[[ISS-005-the-method-lint-imports-dashboard-code]]", "[[STK-012-maintainers]]"]
tags: [constraint]
category: technical
---

# The dashboard depends on the metamodel, never the reverse

**Constraint.** The dependency runs from the dashboard to the Systems42 metamodel. The Systems42 metamodel and method tools must work without dashboard code.

- The dashboard must read section ids, titles, folders and scope, and type prefixes, folders and labels from the metamodel of the repository it runs on.
- It may assume the three areas Requirements, Architecture and Commons.
- The dashboard is developed and tested against the metamodel of `systems42-org/meta`.

**Rationale / origin.** Gernot Starke set this on 2026-11-17 ([[SRC-027-dashboard-distribution-and-metamodel-contract]]). [[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]] rules which wiki a requirement belongs to. This constraint rules the code.

**Impact.** The metamodel defines which sections exist. The dashboard may use a section id to choose routes, colours, navigation labels and tile layout. Sections without a dedicated presentation must still open through the generic route with their area's colours ([[FR-044-sections-come-from-the-repositorys-metamodel]], [[SRC-055-recovery-report-systems42-dashboard]]).

The recovery report found evidence that the method lint runs independently of the dashboard. The closing round kept [[ISS-005-the-method-lint-imports-dashboard-code]] open ([[SRC-055-recovery-report-systems42-dashboard]]).
