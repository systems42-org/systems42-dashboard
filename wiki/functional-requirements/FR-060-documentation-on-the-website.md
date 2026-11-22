---
id: FR-060
type: functional-requirement
title: Documentation on the website
status: draft
created: 2026-11-21
updated: 2026-11-21
sources: ["[[SRC-037-a-public-website-for-the-dashboard]]", "[[SRC-038-grilling-session-on-the-public-website]]"]
related: ["[[FR-031-branding-is-configuration]]", "[[FR-045-a-prompt-template-for-a-brand]]", "[[FR-046-shared-session-in-a-workshop]]", "[[CON-005-the-dashboard-works-on-systems42-derivatives-only]]", "[[CON-001-proof-of-concept-not-production-ready]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]"]
tags: ["functional-requirement", "website"]
notation: agile
level: feature
parent: ["[[FR-056-a-public-website-for-the-dashboard]]"]
priority: Should
release: unscheduled
lane: backbone
order: 60
goal: ["[[GOAL-002-show-what-systems42-can-do]]"]
---

# Documentation on the website

## Story

As a [[STK-010-operators|person who sets up a project wiki]] I want **the configuration, branding and workshop use explained on the site**, so that **I can set up and run the dashboard without asking**.

**PROBLEM / GOAL**

- **Configuration.** The keys of `_system/wiki.yaml`: `system_name`, `tagline`, `dashboard_version`, `brand`, `intro`, `about`, each with its purpose and an example.
- **What a wiki must hold.** What the dashboard needs to find in a repository ([[CON-005-the-dashboard-works-on-systems42-derivatives-only]]).
- **Branding.** The files of a brand folder, the rules for the intro, and that a missing or incomplete brand falls back to the shipped one ([[FR-031-branding-is-configuration]]).
- **Workshop.** Starting on the facilitator's laptop, joining by QR code, the Keyholder, the View, Disconnect all, and that the dashboard stops when the last tab closes ([[FR-046-shared-session-in-a-workshop]]).
- **Limits.** The dashboard is read-only and has no login, so a live session belongs on a trusted network ([[CON-001-proof-of-concept-not-production-ready]]).
- **Guides.** The Getting Started guide and the brand prompt template ([[FR-045-a-prompt-template-for-a-brand]]) as pages of their own, taken from `docs/` of the repository.

**Success metric(s).** Every key the dashboard reads from `_system/wiki.yaml` is explained on the page. The two guides show the text of their files in `docs/`.

**Scope.** in: the documentation page and the two guides · out: the method itself, which the demo's Method and Help pages explain.

## Hierarchy

- **Parent:** [[FR-056-a-public-website-for-the-dashboard]]
- **Children:** none.

> [!note] Open points
> - The page recommends the static export for publishing a wiki. That goes further than [[FR-058-a-demo-to-try-without-installing]] ([issue #86](https://github.com/systems42-org/systems42-dashboard/issues/86)).
> - The site, the README and the help page describe the same things in their own words, and nothing checks that they agree ([issue #86](https://github.com/systems42-org/systems42-dashboard/issues/86)).

## History

> Stated by Gernot Starke on 2026-11-21 and read from the existing site ([[SRC-037-a-public-website-for-the-dashboard]]). Priority agreed on 2026-11-21 ([[SRC-038-grilling-session-on-the-public-website]]).
