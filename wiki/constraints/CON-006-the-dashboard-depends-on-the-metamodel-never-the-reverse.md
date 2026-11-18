---
id: CON-006
type: constraint
title: The dashboard depends on the metamodel, never the reverse
status: draft
created: 2026-11-17
updated: 2026-11-17
sources: ["[[SRC-027-dashboard-distribution-and-metamodel-contract]]", "[[SRC-028-grilling-session-on-dashboard-distribution]]"]
related: ["[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]", "[[FR-044-sections-come-from-the-repositorys-metamodel]]", "[[FR-043-the-dashboard-checks-the-metamodel-version]]", "[[ISS-005-the-method-lint-imports-dashboard-code]]", "[[STK-012-maintainers]]"]
tags: [constraint]
category: technical
---

# The dashboard depends on the metamodel, never the reverse

**Constraint.**
- The dashboard code holds no metamodel facts: no section ids, titles, folders or scope, no type prefixes, folders or labels. It reads them from the repository it runs on.
- It may assume the three areas Requirements, Architecture and Commons.
- Presentation stays in the dashboard: routes, colours, navigation labels, tile layout.
- Nothing in the Systems42 method depends on dashboard code.
- The dashboard is developed and tested against the metamodel of `systems42-org/meta`.

**Rationale / origin.** Gernot Starke set this on 2026-11-17 ([[SRC-027-dashboard-distribution-and-metamodel-contract]]). [[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]] rules which wiki a requirement belongs to. This constraint rules the code.

**Impact.** The constraint does not hold on 2026-11-17 (`main` 53d2920):
- `catalog.py` hard-codes the sections, and `app.py` the type prefixes, folders and labels (`_TYPE_FOLDER`, `_TYPE_LABEL`, `FOLDER_LABELS`). [[FR-044-sections-come-from-the-repositorys-metamodel]] removes the first.
- The method's `metamodel-lint.py` imports `catalog.py` ([[ISS-005-the-method-lint-imports-dashboard-code]]).
