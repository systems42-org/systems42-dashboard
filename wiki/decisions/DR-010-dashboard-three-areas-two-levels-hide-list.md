---
id: DR-010
type: decision-record
title: "The dashboard follows the Systems42 sections diagram — three areas, two levels, a hide list the dashboard itself writes"
status: accepted
created: 2026-10-11
updated: 2026-11-19
sources: ["[[SRC-034-pages-moved-from-meta]]"]
related: ["[[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]]", "[[FR-017-browse-by-area-and-section]]", "[[FR-046-shared-session-in-a-workshop]]"]
tags: [decision-record]
aliases: ["meta DR-033"]
kind: architecture
decided: 2026-10-11
decision-makers: []
consulted: []
informed: []
drivers: []
amends: ["[[DR-008-dashboard-req42-home-and-visual-identity]]", "[[DR-006-dashboard-self-shutdown-lifecycle]]"]
superseded-by: []
---

# The dashboard follows the Systems42 sections diagram — three areas, two levels, a hide list the dashboard itself writes

> follows [[MADR]] · moved from meta [DR-033](https://github.com/systems42-org/meta/blob/main/wiki/decisions/DR-033-dashboard-three-areas-two-levels-hide-list.md) on 2026-11-19

> Changed in part: [[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard|DR-002]] and
> [[FR-046-shared-session-in-a-workshop]] change point 4. The view lasts until the
> dashboard stops and is written to no file. Not built yet.

**Status note (as an ADR):** amends points 1 and 9 of [[DR-008-dashboard-req42-home-and-visual-identity|DR-008]] and the "read-only" statement of [[DR-006-dashboard-self-shutdown-lifecycle|DR-006]]; leaves [[DR-009-dashboard-short-nav-and-command-k-search|DR-009]] intact

## Context and Problem Statement
Systems42 covers requirements (req42), architecture (arc42) and a Common layer
of sections both use. The dashboard showed only the req42 side, as eleven home
tiles in req42 block order ([[DR-008-dashboard-req42-home-and-visual-identity|DR-008]]), and told a different story from the
published sections diagram, which moves Stakeholders, Scope, Quality,
Constraints, Domain Terms and Risks into a Common cabinet (R1–R6, A1–A6,
C1–C6). Small projects also need to reduce what the dashboard shows, and the
footer had accumulated four controls.

## Considered Options

Not recorded at the time.

## Decision Outcome
1. **One section catalog** (`catalog.py`) with three areas and eighteen
   sections from the diagram replaces `REQ42_BLOCKS` and the home tile list.
   Method ADRs under `_system/adr/` stay outside A6 (ISS-018).
2. **Two levels.** Home shows Requirements and Architecture as two peaks (Twin
   Peaks), the *valley* between them (vault status, latest changes, open
   issues, method ADRs) and Commons full-width underneath. Area pages
   `/req42`, `/arc42`, `/commons` show section tiles. Section routes are
   unchanged; `/req42` changes meaning from reading-order overview to area page.
3. **Architecture ships visible and empty** ("not captured yet") so adding the
   arc42 content types later is a catalog change.
4. **Visibility is a hide list** in `_system/dashboard.yaml` — the only file
   the dashboard writes, rewritten in place from a facilitator-only Configure
   dialog. Hidden sections keep their routes and search hits. `wiki.yaml`
   stays identity only. `make new` creates the file; `make sync` leaves it.
5. **Hamburger menu** (Configure · Theme · Who's here · Help · Reload ·
   Disconnect all) replaces the footer buttons; footer reads "wiki dashboard"
   and "wiki read-only". A `/help` page explains the dashboard and the model.
6. **Area colours** (green req — req42's colour, blue arc — arc42's colour, red org) mean place, not action:
   tile eyebrows and top hairlines, area heading band, a 3 px bar under the
   topbar. Shared sections use two solid halves, never a gradient.

### Consequences
- The dashboard is no longer strictly read-only: it writes `dashboard.yaml`,
  via a read-write bind mount of that one file. Everything else stays `:ro`.
- Nav ([[DR-009-dashboard-short-nav-and-command-k-search|DR-009]]) keeps Stakeholders, Quality and Issues on top although they
  now belong to Commons — the nav is about frequency, not ownership.
- Out-of-scope req42 sections (R2, R5, R6) still render as inactive tiles; a
  project hides them with `hidden: [R2, R5, R6]`.
- The spec named the settings endpoint `/config`; it is implemented as
  `/settings` to avoid confusion with the `/config/` mount path inside the
  container.
- Follow-on: arc42 content types and solution-decision records, prototyped in a
  fresh `/new-project` vault and synced back; then A1–A6 get folders.
- `tests/test_catalog.py`, `test_dashboard_config.py`, `test_areas.py`,
  `test_home_layout.py`, `test_menu.py`, `test_help.py`, `test_area_chrome.py`
  pin this decision.
