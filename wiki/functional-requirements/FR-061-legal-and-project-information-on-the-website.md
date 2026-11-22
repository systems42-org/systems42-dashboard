---
id: FR-061
type: functional-requirement
title: Legal and project information on the website
status: draft
created: 2026-11-21
updated: 2026-11-21
sources: ["[[SRC-037-a-public-website-for-the-dashboard]]", "[[SRC-038-grilling-session-on-the-public-website]]"]
related: ["[[STK-020-data-protection-and-security-officers]]"]
tags: ["functional-requirement", "website"]
notation: agile
level: feature
parent: ["[[FR-056-a-public-website-for-the-dashboard]]"]
priority: Must
release: unscheduled
lane: backbone
order: 61
goal: ["[[GOAL-002-show-what-systems42-can-do]]"]
---

# Legal and project information on the website

## Story

As a [[STK-013-people-learning-or-presenting-systems42|visitor of the site]] I want **to see who runs the site and what it records about me**, so that **I can trust it and reach the project**.

**PROBLEM / GOAL**

- **Imprint.** The site has an imprint that meets German law (§ 5 DDG).
- **Privacy notice.** It says who hosts the site, which access data the host may record, and what the demo stores in the visitor's browser.
- **No tracking.** The site sets no cookies and loads no tracking, analytics or advertising scripts.
- **Project links.** Every page links to the repository, the releases and the issue tracker on GitHub, and to the method family: systems42.org, arc42.org, docs.arc42.org, req42.de, quality.arc42.org.
- **Who keeps it correct.** Gernot Starke, whom the imprint names, is responsible for the imprint and the privacy notice. It concerns [[STK-020-data-protection-and-security-officers]].

**Success metric(s).** Every page links to the imprint and privacy page. Loading any page of the site sets no cookie and asks no other server for anything.

**Scope.** in: imprint, privacy notice, project links · out: a licence choice, terms of use.

## Hierarchy

- **Parent:** [[FR-056-a-public-website-for-the-dashboard]]
- **Children:** none.

## History

> Stated by Gernot Starke on 2026-11-21 and read from the existing site ([[SRC-037-a-public-website-for-the-dashboard]]). He decided on 2026-11-21 that he keeps both texts correct, and that this feature is Must because a public site under German law needs an imprint ([[SRC-038-grilling-session-on-the-public-website]]).
