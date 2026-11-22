---
id: CTX-001
type: context
title: Systems42 Dashboard Context
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-043-context-of-the-systems42-dashboard]]", "[[SRC-045-grilling-session-on-context-and-building-blocks]]"]
related: ["[[EIF-001-systems42-wiki]]", "[[STK-001-readers]]", "[[STK-008-workshop-participants-and-facilitators]]", "[[STK-010-operators]]", "[[STK-013-people-learning-or-presenting-systems42]]", "[[STK-023-keyholder]]", "[[CON-001-proof-of-concept-not-production-ready]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]", "[[CON-005-the-dashboard-works-on-systems42-derivatives-only]]", "[[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]]", "[[QR-004-the-wikis-content-stays-on-the-machine]]", "[[FR-056-a-public-website-for-the-dashboard]]"]
tags: [context]
kind: business
diagram: generated
---

# Systems42 Dashboard Context

**Diagram.** _Projected_: generated from external interface flows (`EIF.flows`) and stakeholder edges (`STK.provides` and `STK.receives`).

**In scope.** The Systems42 dashboard reads a local Systems42 requirements wiki and serves its pages, lists, matrices, diagrams, search results and method help in a browser. It runs locally and offline ([[QR-004-the-wikis-content-stays-on-the-machine]]), supports shared read-only workshop sessions on a trusted network ([[CON-001-proof-of-concept-not-production-ready]]) and exports a static live demo for the public website ([[FR-056-a-public-website-for-the-dashboard]]).

**Out of scope.**
- Editing, creating or deleting wiki pages or raw sources ([[CON-002-dashboard-never-writes-to-the-wiki]]).
- Defining or changing the Systems42 metamodel ([[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]], [[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]]).
- Serving non-Systems42 Markdown folders or general Obsidian vaults ([[CON-005-the-dashboard-works-on-systems42-derivatives-only]]).
- Authentication, access control or public internet multi-user hosting ([[CON-001-proof-of-concept-not-production-ready]]).
- Cloud storage, user accounts or external telemetry ([[QR-004-the-wikis-content-stays-on-the-machine]]).

**External interfaces.**
- [[EIF-001-systems42-wiki]]: local Systems42 derivative repository, inbound read-only (wiki pages, metamodel definitions, wiki and brand configuration).

**User roles.**
- [[STK-001-readers]], [[STK-008-workshop-participants-and-facilitators]] and [[STK-013-people-learning-or-presenting-systems42]]: read wiki pages, diagrams, search results and open issues in a browser (merged as one Reader role in the diagram).
- [[STK-010-operators]]: start, stop and clean up the local dashboard runtime and receive its local address and QR code.
- [[STK-023-keyholder]]: controls visibility settings and ends a shared workshop session while reading the wiki.

**Explanation.** The dashboard has a single external neighbouring system, [[EIF-001-systems42-wiki]], and reads it without writing back ([[CON-002-dashboard-never-writes-to-the-wiki]]). Release registries (GitHub Releases, GHCR) and GitHub Pages are distribution and hosting infrastructure rather than runtime external neighbours, because the running dashboard works offline once installed ([[QR-004-the-wikis-content-stays-on-the-machine]]).
