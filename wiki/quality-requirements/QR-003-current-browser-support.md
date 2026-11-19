---
id: QR-003
type: quality-requirement
title: Current browser support
status: draft
created: 2026-10-18
updated: 2026-11-19
sources: ["[[SRC-034-pages-moved-from-meta]]"]
related: ["[[DR-006-dashboard-self-shutdown-lifecycle]]", "[[QR-001-usable-on-phone-and-tablet]]", "[[STK-007-workshop-facilitators]]", "[[STK-008-workshop-participants]]"]
tags: [quality-requirement]
dimensions: [flexible, reliable]
priority: must
testable: true
---

# Current browser support

**Q42 dimensions.** Flexible, reliable.

The dashboard behaves the same in every current browser, not only in the one it was built with. Supported are the latest two stable versions of Firefox, Chrome, Edge and Safari on the desktop, and of Safari (iOS) and Chrome (Android).

**Scenario (Q42 quality scenario).**  <!-- follows [[Q42]], https://quality.arc42.org -->
- **Source.** A [[STK-007-workshop-facilitators|workshop facilitator]] on a laptop, or a [[STK-008-workshop-participants|workshop participant]] on a phone.
- **Stimulus.** Opens and uses the dashboard in a supported browser.
- **Environment.** A normal workshop. The dashboard runs on the facilitator's machine.
- **Response.** Every page renders and works, on a phone too ([[QR-001-usable-on-phone-and-tablet]]). The dashboard keeps running while one of its pages is open, also after Back, Forward, a reload or 5 minutes in a background tab. Once the last page closes, it stops itself ([[DR-006-dashboard-self-shutdown-lifecycle]]).
- **Measure.** All of this holds in every supported browser. The stop comes within 30 s of the last page closing.

**Verification.** A manual check before each release, on a desktop and on a real iPhone and Android phone.

> [!note] History
> Moved from meta [QR-004](https://github.com/systems42-org/meta/blob/main/wiki/quality-requirements/QR-004-current-browser-support.md) on 2026-11-19 and shortened. It was raised after Firefox stopped the dashboard while a page was still open (meta [SRC-011](https://github.com/systems42-org/meta/blob/main/raw/sources/SRC-011-dashboard-firefox-shutdown.md)).
