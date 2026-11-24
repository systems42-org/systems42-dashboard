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

**Constraint.**
- The dashboard reads section ids, titles, folders and scope, and type prefixes, folders and labels from the repository it runs on. It may use a section id to select its presentation, such as routes, colours, navigation labels and tile layout. A section it does not know still opens through the generic route with its area's colours ([[SRC-055-recovery-report-systems42-dashboard]]).
- It may assume the three areas Requirements, Architecture and Commons.
- Presentation stays in the dashboard: routes, colours, navigation labels, tile layout.
- Nothing in the Systems42 method depends on dashboard code.
- The dashboard is developed and tested against the metamodel of `systems42-org/meta`.

**Rationale / origin.** Gernot Starke set this on 2026-11-17 ([[SRC-027-dashboard-distribution-and-metamodel-contract]]). [[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]] rules which wiki a requirement belongs to. This constraint rules the code.

**Impact.** Presentation keyed by a known section id is allowed. The fallback keeps unknown sections visible without making the metamodel depend on dashboard code ([[FR-044-sections-come-from-the-repositorys-metamodel]]). [[ISS-005-the-method-lint-imports-dashboard-code]] remains open; the recovery report found evidence against it but the human chose to leave it open ([[SRC-055-recovery-report-systems42-dashboard]]).
