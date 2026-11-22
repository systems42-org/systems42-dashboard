---
id: FR-057
type: functional-requirement
title: Overview of the dashboard on the website
status: draft
created: 2026-11-21
updated: 2026-11-21
sources: ["[[SRC-037-a-public-website-for-the-dashboard]]", "[[SRC-038-grilling-session-on-the-public-website]]"]
related: ["[[FR-058-a-demo-to-try-without-installing]]", "[[FR-059-downloads-on-the-website]]", "[[FR-060-documentation-on-the-website]]"]
tags: ["functional-requirement", "website"]
notation: agile
level: feature
parent: ["[[FR-056-a-public-website-for-the-dashboard]]"]
priority: Should
release: unscheduled
lane: backbone
order: 57
goal: ["[[GOAL-002-show-what-systems42-can-do]]"]
---

# Overview of the dashboard on the website

## Story

As a [[STK-013-people-learning-or-presenting-systems42|person who considers using Systems42]] I want **the first page to say what the dashboard is and what I can do next**, so that **I know within a minute whether it is worth a look**.

**PROBLEM / GOAL**

- **What it is.** One sentence: a read-only view in the browser of a requirements and architecture wiki written in Markdown.
- **What a reader can do with it.** Search that forgives typos, tracing from goals to requirements and building blocks, one shared view in a workshop.
- **Next steps.** From the first screen the visitor reaches the demo ([[FR-058-a-demo-to-try-without-installing]]), the downloads ([[FR-059-downloads-on-the-website]]) and the documentation ([[FR-060-documentation-on-the-website]]) with one click each.
- **Release.** It shows the current release number.
- **Two steps to start.** Get the launcher and name a release in `_system/wiki.yaml`, then start it.

**Success metric(s).** The first screen names the dashboard in one sentence and holds three links: demo, downloads, documentation. The release number equals the newest release.

**Scope.** in: the overview page · out: the pages it links to.

## Hierarchy

- **Parent:** [[FR-056-a-public-website-for-the-dashboard]]
- **Children:** none.

> [!note] Open points
> - The two steps name Docker only ([issue #86](https://github.com/systems42-org/systems42-dashboard/issues/86)).

## History

> Stated by Gernot Starke on 2026-11-21 and read from the existing site ([[SRC-037-a-public-website-for-the-dashboard]]). Priority agreed on 2026-11-21 ([[SRC-038-grilling-session-on-the-public-website]]).
