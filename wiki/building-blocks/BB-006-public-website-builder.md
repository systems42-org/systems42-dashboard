---
id: BB-006
type: building-block
title: Public website builder
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-044-building-blocks-of-the-systems42-dashboard]]", "[[SRC-045-grilling-session-on-context-and-building-blocks]]"]
related: ["[[SOL-001-systems42-dashboard]]", "[[STK-012-maintainers]]", "[[STK-013-people-learning-or-presenting-systems42]]"]
tags: [building-block]
parent: "[[CTX-001-systems42-dashboard-context]]"
drivers: ["[[GOAL-002-show-what-systems42-can-do]]", "[[FR-056-a-public-website-for-the-dashboard]]", "[[FR-057-overview-of-the-dashboard-on-the-website]]", "[[FR-058-a-demo-to-try-without-installing]]", "[[FR-059-downloads-on-the-website]]", "[[FR-060-documentation-on-the-website]]", "[[FR-061-legal-and-project-information-on-the-website]]", "[[FR-062-the-website-is-built-and-published-from-the-repository]]", "[[QR-001-usable-on-phone-and-tablet]]"]
decisions: ["[[DR-005-the-dashboard-lives-in-its-own-repository]]"]
uses: ["[[BB-001-python-dashboard]]", "[[EIF-001-systems42-wiki]]"]
location: site/
state: current
superseded-by:
---

# Public website builder

> follows [[arc42]] (section 5, black box)

## Purpose / Responsibility

Static-site builder (`site/build.py`), Jinja templates and Docker wrapper scripts (`site/build.sh`, `site/serve.sh`) that produce `dashboard.systems42.org` for GitHub Pages ([[FR-056-a-public-website-for-the-dashboard]], [[FR-062-the-website-is-built-and-published-from-the-repository]]). It renders the overview, downloads, documentation and legal pages and imports [[BB-001-python-dashboard]] directly to export a browsable static live demo of this repository's wiki ([[FR-058-a-demo-to-try-without-installing]]).

## Interfaces

- **Provides:** Static HTML, CSS and assets in `site/_site/`, built and checked for broken internal links in CI and locally via `make site` and `make site-show`.
- **Needs:** [[BB-001-python-dashboard]] (imported in-process to render every demo route), [[EIF-001-systems42-wiki]] (this repository's own wiki and `docs/`), and Docker for reproducible local builds.

## Quality / Performance

Verifies every internal link in the generated site and fails the build on any broken target. Outputs plain static files with no cookies, tracking scripts or external CDNs ([[FR-061-legal-and-project-information-on-the-website]], [[QR-001-usable-on-phone-and-tablet]]).
