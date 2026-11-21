---
id: FR-056
type: functional-requirement
title: A public website for the dashboard
status: draft
created: 2026-11-21
updated: 2026-11-21
sources: ["[[SRC-037-a-public-website-for-the-dashboard]]", "[[SRC-038-grilling-session-on-the-public-website]]"]
related: ["[[STK-013-people-learning-or-presenting-systems42]]", "[[STK-010-operators]]", "[[STK-012-maintainers]]", "[[CON-001-proof-of-concept-not-production-ready]]", "[[QR-001-usable-on-phone-and-tablet]]", "[[FR-010-show-the-method]]", "[[FR-029-the-dashboard-as-a-product]]"]
tags: ["functional-requirement", "website"]
stereotype: epic
parent: []
priority: Should
release: unscheduled
lane: backbone
order: 56
goal: ["[[GOAL-002-show-what-systems42-can-do]]"]
---

# A public website for the dashboard

## Epic: Summary

As a [[STK-013-people-learning-or-presenting-systems42|person who considers using Systems42]] I want **a public website that says what the dashboard is, lets me try it and tells me how to run it**, so that **I can judge it before I install anything**.

**PROBLEM / GOAL**

Until the site existed, a person had to clone a repository and start Docker before seeing a single page. The site is at `dashboard.systems42.org`.

These rules hold for every feature below:

- **For three groups.** People who consider using Systems42, people who run a dashboard ([[STK-010-operators]]) and the maintainers who publish a release ([[STK-012-maintainers]]).
- **On every page.** A header with the name, the release number and the navigation: Overview, Docs, Downloads, GitHub, Live Demo. A footer with the release number and the date the site was built.
- **English.** The site is in English.
- **Usable on a phone.** The site meets [[QR-001-usable-on-phone-and-tablet]]. It has no measure of its own for speed or availability.
- **No tracking.** The site sets no cookies and loads no tracking, analytics or advertising scripts ([[FR-061-legal-and-project-information-on-the-website]]).

**Success metric(s).** A person who has never seen the dashboard opens the site, reads a page of the demo and finds the command that starts the dashboard, without installing anything and without an account.

**Scope.** in: overview, demo, downloads, documentation, legal information, building and publishing · out: publishing any other wiki as a static site (the export is, for now, only the way this site gets its demo), a measure for speed or availability, other languages.

## Hierarchy

- **Parent:** none (epic).
- **Children:** projected from the `parent:` backlinks: [[FR-057-overview-of-the-dashboard-on-the-website]], [[FR-058-a-demo-to-try-without-installing]], [[FR-059-downloads-on-the-website]], [[FR-060-documentation-on-the-website]], [[FR-061-legal-and-project-information-on-the-website]], [[FR-062-the-website-is-built-and-published-from-the-repository]].

> [!note] Open points
> - Three gaps of the existing site are tracked in [issue #86](https://github.com/systems42-org/systems42-dashboard/issues/86): it names Docker as the only way to start, it has no tests in the test suite, and nothing checks that the site, the README and the help page agree.

## History

> Stated by Gernot Starke on 2026-11-21 and read from the existing site ([[SRC-037-a-public-website-for-the-dashboard]]). He decided the goal, the audience, the scope of the export and the priorities on the same day ([[SRC-038-grilling-session-on-the-public-website]]).
