---
id: DR-008
type: decision-record
title: The public website is built by a custom Python script for GitHub Pages
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-039-solution-strategy-of-the-dashboard]]", "[[SRC-046-grilling-session-on-modularizing-the-solution-strategy]]"]
related: ["[[BB-006-public-website-builder]]", "[[BB-001-python-dashboard]]", "[[FR-057-overview-of-the-dashboard-on-the-website]]", "[[FR-059-downloads-on-the-website]]", "[[FR-060-documentation-on-the-website]]", "[[FR-061-legal-and-project-information-on-the-website]]", "[[QR-001-usable-on-phone-and-tablet]]"]
tags: [decision-record]
aliases: []
kind: architecture
decided: 2026-11-22
decision-makers: [Gernot Starke]
consulted: [Claude]
informed: []
drivers: ["[[GOAL-002-show-what-systems42-can-do]]", "[[FR-056-a-public-website-for-the-dashboard]]", "[[FR-058-a-demo-to-try-without-installing]]", "[[FR-062-the-website-is-built-and-published-from-the-repository]]"]
amends: []
superseded-by: []
---

# The public website is built by a custom Python script for GitHub Pages

> follows [[MADR]]

## Context and Problem Statement

The dashboard needs a public website at `dashboard.systems42.org` so people can see the product, browse a live demo and read install instructions before installing anything ([[FR-056-a-public-website-for-the-dashboard]], [[FR-058-a-demo-to-try-without-installing]]). The live demo must render the exact pages of the dashboard itself.

How should the public website and its live demo be built and hosted?

## Decision Drivers

- A visitor must try the dashboard without installing anything or creating an account ([[GOAL-002-show-what-systems42-can-do]], [[FR-058-a-demo-to-try-without-installing]]).
- Every change on `main` should build and publish automatically from this repository with no server to maintain ([[FR-062-the-website-is-built-and-published-from-the-repository]]).
- The site must not require running an unauthenticated dashboard server on the public internet ([[CON-001-proof-of-concept-not-production-ready]]).

## Considered Options

1. **Custom Python build script (`site/build.py`) plus GitHub Pages.** A Python script renders the few site pages with Jinja and imports [[BB-001-python-dashboard]] directly to export the live demo as static HTML. GitHub Actions builds and publishes the output to GitHub Pages.
2. **Static site generator (Jekyll, Hugo or MkDocs) plus a separate demo exporter.** A site generator builds the marketing and documentation pages, while a separate Python step exports the dashboard demo and merges the two outputs.
3. **Hosted live dashboard server.** Run the dashboard container on a public server behind a reverse proxy for the demo alongside a static site.

## Decision Outcome

Chosen option: **1, custom Python build script plus GitHub Pages**, because the demo can only be produced by the dashboard's own code. That export already requires Python and Jinja, and the remaining website pages are few enough to share the same template language without introducing a second build toolchain. Hosting static files on GitHub Pages eliminates server operations, hosting cost and public-server security exposure.

### Consequences

- Good: one build tool (Python and Jinja) produces both the website and the live demo inside [[BB-006-public-website-builder]].
- Good: zero server operations and zero hosting cost on GitHub Pages.
- Good: the build script checks every internal link across the site and demo before publishing.
- Bad: website layout features that a site generator ships out of the box (feeds, pagination, blog archives) would have to be built manually if ever needed.
- Bad: the demo export is coupled to [[BB-001-python-dashboard]]'s Python internals and does not exercise interactive workshop sessions.

### Confirmation

`make site` and the GitHub Actions `site` workflow run `site/build.py` on every pull request and push to `main` and fail if any internal link in the exported site or demo is broken.

## More Information

Confirmed by Gernot Starke on 2026-11-22 in [[SRC-039-solution-strategy-of-the-dashboard]] and moved from solution strategy to a standalone decision record in [[SRC-046-grilling-session-on-modularizing-the-solution-strategy]].
