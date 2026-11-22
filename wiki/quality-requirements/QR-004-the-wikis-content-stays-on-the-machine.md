---
id: QR-004
type: quality-requirement
title: The wiki's content stays on the machine
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-039-solution-strategy-of-the-dashboard]]", "[[SRC-040-grilling-session-on-the-solution-strategy]]"]
related: ["[[STK-020-data-protection-and-security-officers]]", "[[STK-008-workshop-participants-and-facilitators]]", "[[FR-029-the-dashboard-as-a-product]]", "[[CON-001-proof-of-concept-not-production-ready]]", "[[FR-061-legal-and-project-information-on-the-website]]", "[[SOL-001-systems42-dashboard]]"]
tags: [quality-requirement]
dimensions: [secure, reliable]
priority: must
testable: true
---

# The wiki's content stays on the machine

**Q42 dimensions.** Secure, reliable.

The dashboard sends nothing to a third party and works without network.

**Scenario (Q42 quality scenario).**  <!-- follows [[Q42]], https://quality.arc42.org -->
- **Source.** A person who reads a wiki with the dashboard, for example a [[STK-008-workshop-participants-and-facilitators|workshop participant]].
- **Stimulus.** Opens every page of the dashboard, for a wiki that holds confidential requirements.
- **Environment.** Docker, uv or the app, after the first start.
- **Response.** The dashboard serves every page from the local machine. It asks for no account and sends nothing to anyone.
- **Measure.** The browser and the dashboard make zero requests to a host other than the local one. With the network cut, every page loads completely.

Two things are outside the measure: the first start with Docker or uv downloads the release, and a link the reader clicks leaves the machine like any link.

**Applies to.** [[FR-029-the-dashboard-as-a-product]] and its features. The public website has its own rules ([[FR-061-legal-and-project-information-on-the-website]]).
**Tensions.** [[CON-001-proof-of-concept-not-production-ready]]: whoever reaches the machine on the local network can read the wiki. This requirement is about third parties, not about the people in the room.

> [!note] History
> Stated by Gernot Starke as a strategy statement ([[SRC-039-solution-strategy-of-the-dashboard]]). Made a quality requirement with priority Must in questions 2 and 3 ([[SRC-040-grilling-session-on-the-solution-strategy]]). It serves the [[STK-020-data-protection-and-security-officers]].
