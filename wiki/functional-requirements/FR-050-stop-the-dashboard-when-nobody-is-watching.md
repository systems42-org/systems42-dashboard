---
id: FR-050
type: functional-requirement
title: Stop the dashboard when nobody is watching
status: draft
created: 2026-11-19
updated: 2026-11-19
sources: ["[[SRC-034-dashboard-requirements-moved-from-meta]]", "[[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]"]
related: ["[[STK-010-people-who-run-the-dashboard]]", "[[FR-016-see-whether-the-page-is-still-connected]]", "[[QR-003-works-in-every-current-browser]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]"]
tags: [functional-requirement, session]
notation: agile
level: story
parent: ["[[FR-046-shared-session-in-a-workshop]]"]
building-blocks: []
priority: Should
release: unscheduled
lane: backbone
order: 50
goal: ["[[GOAL-008-one-way-into-every-systems42-wiki]]"]
---

# Stop the dashboard when nobody is watching

## Story

> follows [[user-story-format]], [[INVEST]]

As a [[STK-010-people-who-run-the-dashboard|person who runs the dashboard]] I want **the dashboard to end by itself when nobody is watching**, so that **no forgotten process holds my port**.

**Acceptance criteria.** > follows [[acceptance-criteria]]

- **Given** a dashboard with open pages **when** the last page is closed **then** the dashboard stops a few seconds later.
- **Given** an open page that is in the background, reloaded or moved with Back and Forward **then** the dashboard keeps running.
- **Given** a dashboard that has started and no page ever connects **then** it stops after a wait of about 90 seconds.
- **Given** the dashboard is started with the stop switched off **when** the last page is closed **then** it keeps running.

**Scope.** in: the stop and the switch · out: the Keyholder's "Disconnect all" ([[FR-046-shared-session-in-a-workshop]]), how presence is measured.

## Hierarchy

- **Parent:** [[FR-046-shared-session-in-a-workshop]]
- **Children:** none.

> [!note] Open points
> - The times are guides, not promises: about 5 seconds after a page says it is leaving, 90 seconds without any sign of a page, a page pings about every 20 seconds. The wait is longer than the browser slows a page in the background, about 60 seconds, so a hidden page does not count as closed.
> - There is no stop button: a page cannot close its own tab, so closing the tab is the gesture.
> - The measure for the stop in every browser is in [[QR-003-works-in-every-current-browser]].

## History

> Moved from the Systems42 method wiki (meta DR-022, self-shutdown) on 2026-11-19, where it was a decision record. Peter Gerstbach decided on 2026-11-19: this is a requirement, not a decision; it can be switched off when the dashboard starts; it hangs under FR-046 ([[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]).
