---
id: QR-001
type: quality-requirement
title: Usable on phone and tablet
status: draft
created: 2026-11-12
updated: 2026-11-12
sources: ["[[SRC-017-usable-on-phone-and-tablet]]", "[[SRC-018-grilling-session-on-phone-and-tablet]]"]
related: ["[[GOAL-003-answers-without-asking-a-colleague]]", "[[GOAL-007-readers-who-come-back]]", "[[STK-008-workshop-participants]]", "[[STK-001-product-owners]]", "[[STK-004-development-teams]]", "[[STK-013-people-learning-or-presenting-systems42]]", "[[DR-003-quality-requirements-are-classified-by-q42-dimensions]]"]
tags: [quality-requirement]
dimensions: [usable, flexible]
priority: should
testable: true
---

# Usable on phone and tablet

**Q42 dimensions.** Usable, flexible.

Every page of the dashboard is easy to read and use on a phone or a tablet, not only on a laptop. The layout adapts to the screen.

**Scenario (Q42 quality scenario).**  <!-- follows [[Q42]], https://quality.arc42.org -->
- **Source.** A [[STK-008-workshop-participants|workshop participant]].
- **Stimulus.** Opens a link to a dashboard page on a phone.
- **Environment.** Phone in portrait, 320 CSS pixels wide, normal workshop use.
- **Response.** The page fits the screen. Search, menu, lists, filters and links all work by touch.
- **Measure.** No page scrolls sideways at 320 CSS pixels (WCAG 2.2, 1.4.10 Reflow). Wide tables may scroll inside their own box. Text is readable without zooming. Every link and button is at least 24 × 24 CSS pixels (WCAG 2.2, 2.5.8). Nothing a laptop reader can do is missing on the phone. Every node of a diagram is also reachable as a text link on the same page.

**Diagrams.** Best effort. On a phone or tablet a diagram first shows whole, fitted to the screen, and the reader zooms and pans it by touch. A large diagram, such as a data model, may stay hard to read on a small screen. The measure above does not cover how readable a diagram is.

**Applies to.** Every page of the dashboard, among them search ([[FR-001-search-the-wiki]]), browsing ([[FR-017-browse-by-area-and-section]]) and the issue list ([[FR-024-see-what-is-still-open]]).
**Tensions.** None known.

> [!note] History
> Raised by Gernot Starke on 2026-11-12 ([[SRC-017-usable-on-phone-and-tablet]]). In [[SRC-018-grilling-session-on-phone-and-tablet]] he chose Q42 dimensions over one ISO 25010 attribute ([[DR-003-quality-requirements-are-classified-by-q42-dimensions]]), 320 pixels as the narrowest width, best effort for diagrams, and Should.
