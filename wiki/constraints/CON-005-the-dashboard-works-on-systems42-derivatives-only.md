---
id: CON-005
type: constraint
title: The dashboard works on Systems42 derivatives only
status: draft
created: 2026-11-17
updated: 2026-11-17
sources: ["[[SRC-027-dashboard-distribution-and-metamodel-contract]]", "[[SRC-028-grilling-session-on-dashboard-distribution]]"]
related: ["[[FR-042-start-a-pinned-release-with-one-command]]", "[[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]]", "[[FR-029-the-dashboard-as-a-product]]", "[[STK-010-operators]]"]
tags: [constraint]
category: technical
---

# The dashboard works on Systems42 derivatives only

**Constraint.** The dashboard assumes that the repository it runs on is a Systems42 derivative: a repository created from Systems42, holding an LLM wiki with a metamodel, requirements and architecture, and its configuration. It finds `wiki/`, `raw/`, `_system/metamodel/`, `_system/anchors/` and `_system/wiki.yaml` by convention.

On any other repository the dashboard says what is missing and stops. It does not guess.

**Rationale / origin.** Gernot Starke set this on 2026-11-17, so that every wiki starts the dashboard the same way and needs no paths of its own ([[SRC-027-dashboard-distribution-and-metamodel-contract]]).

**Impact.**
- The launcher passes one repository instead of a path per folder ([[FR-042-start-a-pinned-release-with-one-command]]).
- A change of this layout in Systems42 needs a dashboard release that follows it.
