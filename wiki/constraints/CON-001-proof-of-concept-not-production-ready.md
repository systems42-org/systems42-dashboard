---
id: CON-001
type: constraint
title: The dashboard is a proof of concept, not production-ready for every environment
status: draft
created: 2026-11-10
updated: 2026-11-10
sources: ["[[SRC-001-stakeholders-of-the-systems42-dashboard]]", "[[SRC-002-grilling-session-on-stakeholders]]"]
related: ["[[STK-001-product-owners]]", "[[STK-004-development-teams]]", "[[STK-020-data-protection-and-security-officers]]", "[[STK-021-builders-of-project-specific-dashboards]]", "[[STK-023-keyholder]]"]
tags: [constraint]
category: organizational
---

# The dashboard is a proof of concept, not production-ready for every environment

**Constraint.** The dashboard is one application. It serves workshops, demos and
everyday work on requirements and architecture, for example by product owners
([[STK-001-product-owners]]) and development teams ([[STK-004-development-teams]]).
It shows what Systems42 makes visible. It is not built to be production-ready for
every environment.

It has no login for now. Use it only on a network you trust.

**Rationale / origin.** Set by Gernot Starke ([[SRC-002-grilling-session-on-stakeholders]]).
The dashboard exists to show the method at work. Projects that need more can build
their own dashboards ([[STK-021-builders-of-project-specific-dashboards]]).

**Impact.**
- Anyone on the same network who knows the address can read everything. The QR
  code on the home page hands out that address. This concerns
  [[STK-020-data-protection-and-security-officers]].
- As built, the dashboard runs on one person's machine and stops a few seconds
  after the last browser tab closes ([[SRC-001-stakeholders-of-the-systems42-dashboard]]).
- Without a login, the Keyholder ([[STK-023-keyholder]]) is whoever connected
  first, not an identified person.

> [!assumption]
> A login could be added later, for example an OAuth sign-in through GitHub, GitLab
> or Forgejo. That this is easy has not been tried.
