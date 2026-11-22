---
id: FR-062
type: functional-requirement
title: The website is built and published from the repository
status: draft
created: 2026-11-21
updated: 2026-11-21
sources: ["[[SRC-037-a-public-website-for-the-dashboard]]", "[[SRC-038-grilling-session-on-the-public-website]]"]
related: ["[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[FR-030-numbered-releases]]", "[[FR-058-a-demo-to-try-without-installing]]"]
tags: ["functional-requirement", "website"]
notation: agile
level: feature
parent: ["[[FR-056-a-public-website-for-the-dashboard]]"]
priority: Should
release: unscheduled
lane: backbone
order: 62
goal: ["[[GOAL-002-show-what-systems42-can-do]]"]
---

# The website is built and published from the repository

## Story

As a [[STK-012-maintainers|maintainer]] I want **the site to be built from the repository and published by itself**, so that **it never says something else than the release does**.

**PROBLEM / GOAL**

- **One source.** The release number, the launcher, the changelog, the guides and the demo come from their one place in the repository. Nothing is written by hand a second time.
- **Nothing changed.** Building the site changes nothing in `wiki/`, `raw/`, `_system/`, `_templates/` or `docs/` ([[CON-002-dashboard-never-writes-to-the-wiki]]).
- **Published by itself.** A change on `main` publishes the site without a manual step. A maintainer can also publish by hand.
- **The build checks itself.** It fails when a required page is missing, when a link inside the site leads nowhere, or when a demo page still tries to reach a running dashboard.
- **Preview.** A maintainer can build the site and look at it locally before it is published.
- **Address.** The site is reachable at `dashboard.systems42.org` over HTTPS.

**Success metric(s).** After a merge to `main` the site shows the release number of `main` without anyone doing anything. A link inside the site that leads nowhere makes the build fail.

**Scope.** in: building, checking, preview, publishing · out: the hosting itself, which is GitHub Pages.

## Hierarchy

- **Parent:** [[FR-056-a-public-website-for-the-dashboard]]
- **Children:** none.

> [!note] Open points
> - The checks run only in the site's own build, not in the test suite ([issue #86](https://github.com/systems42-org/systems42-dashboard/issues/86)).

## History

> Stated by Gernot Starke on 2026-11-21 and read from the existing site ([[SRC-037-a-public-website-for-the-dashboard]]). Priority agreed on 2026-11-21 ([[SRC-038-grilling-session-on-the-public-website]]).
