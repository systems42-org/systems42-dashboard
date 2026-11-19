---
id: QR-003
type: quality-requirement
title: Works in every current browser
status: draft
created: 2026-11-19
updated: 2026-11-19
sources: ["[[SRC-034-dashboard-requirements-moved-from-meta]]", "[[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]"]
related: ["[[FR-050-stop-the-dashboard-when-nobody-is-watching]]", "[[QR-001-usable-on-phone-and-tablet]]", "[[QR-002-runs-alike-on-linux-and-macos]]", "[[STK-008-workshop-participants-and-facilitators]]"]
tags: [quality-requirement]
dimensions: [flexible, reliable]
priority: should
testable: true
---

# Works in every current browser

**Q42 dimensions.** Flexible, reliable.

The dashboard behaves the same in every current desktop and mobile browser, not only in the one it was built with.

**Supported browsers.** The latest two stable major versions, at release time, of:
- **Desktop:** Firefox, Chrome, Edge, Safari (macOS).
- **Mobile:** Safari (iOS), Chrome (Android). Workshop participants join from their phones with the QR code ([[FR-046-shared-session-in-a-workshop]]).

**Scenario (Q42 quality scenario).**  <!-- follows [[Q42]], https://quality.arc42.org -->
- **Source.** A [[STK-008-workshop-participants-and-facilitators|workshop facilitator]] on a laptop, or a [[STK-008-workshop-participants-and-facilitators|participant]] on a phone.
- **Stimulus.** Opens and uses the dashboard in any supported browser.
- **Environment.** A normal workshop; the dashboard runs on the facilitator's machine.
- **Response.**
  1. Every page renders and is usable: navigation, search, diagrams and graphs, the theme switch. On a phone at phone width nothing scrolls sideways ([[QR-001-usable-on-phone-and-tablet]]).
  2. The dashboard keeps running while at least one page is open, including Back and Forward, reload and a tab left in the background for 5 minutes.
  3. Once the last page is closed, the dashboard stops itself ([[FR-050-stop-the-dashboard-when-nobody-is-watching]]).
- **Measure.** All three hold in every supported browser. The stop in 3 happens within **30 seconds** of the last page closing.

**Verification.** For now a manual check before each release, on desktop and on a real iPhone and Android phone. Automated cross-browser tests are a later option, not part of this requirement.

**Applies to.** Every page of the dashboard.
**Tensions.** Newer browser features against the oldest supported Safari version.

> [!note] History
> Moved from the Systems42 method wiki (meta QR-004) on 2026-11-19. It exists because in Firefox the dashboard stopped itself while a page was still open: Back and Forward restored the previous page without it reporting itself as open again. Nobody noticed at first, because day-to-day use was in Chrome. Peter Gerstbach decided on 2026-11-19: one quality requirement ([[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]).
