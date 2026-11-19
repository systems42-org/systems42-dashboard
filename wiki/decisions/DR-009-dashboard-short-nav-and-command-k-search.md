---
id: DR-009
type: decision-record
title: "The dashboard nav holds five sections, the home page shows the brand once, and ⌘K focuses search"
status: accepted
created: 2026-10-10
updated: 2026-11-19
sources: ["[[SRC-034-pages-moved-from-meta]]"]
related: ["[[FR-014-reach-the-main-content-from-the-header]]", "[[FR-001-search-the-wiki]]"]
tags: [decision-record]
aliases: ["meta DR-032"]
kind: architecture
decided: 2026-10-10
decision-makers: []
consulted: []
informed: []
drivers: []
amends: ["[[DR-008-dashboard-req42-home-and-visual-identity]]"]
superseded-by: []
---

# The dashboard nav holds five sections, the home page shows the brand once, and ⌘K focuses search

> follows [[MADR]] · moved from meta [DR-032](https://github.com/systems42-org/meta/blob/main/wiki/decisions/DR-032-dashboard-short-nav-and-command-k-search.md) on 2026-11-19

> Replaced in part: point 1, the five nav entries, is now
> [[FR-014-reach-the-main-content-from-the-header]] (Requirements · Architecture · Glossary · Decisions · Issues).
> Points 2 and 3 still hold.

**Status note (as an ADR):** amends point 2 of [[DR-008-dashboard-req42-home-and-visual-identity|DR-008]]

## Context and Problem Statement
[[DR-008-dashboard-req42-home-and-visual-identity|DR-008]] gave every page a
persistent nav carrying the whole req42 reading order (nine entries) and made
`/` the search shortcut. Reviewing the home page after the Systems42 mark
replaced the placeholder artwork showed two problems:

- The home page showed mark and system name twice, stacked: once in the
  topbar brand and once in the hero directly beneath it.
- Nine nav entries duplicate the home tiles, which already follow the req42
  reading order, and crowd the top row on a projector. The human asked which
  sections are important enough to be one click away from everywhere.

## Considered Options

Not recorded at the time.

## Decision Outcome
1. **Five nav entries: Goals · Stakeholders · Backlog · Quality · Issues.**
   These are the sections a requirements workshop keeps returning to: why
   (goals), for whom (stakeholders), what (backlog), how well (quality), and
   what is unresolved (issues). Quality stays on top deliberately — it is the
   section most often neglected and the one architects need first. Scope,
   Glossary, ADRs and the req42 reading-order page are reached from the home
   tiles and from a footer link row.
2. **The topbar brand is omitted on the home page.** There the hero carries
   mark, name and tagline; on every other page the brand remains the way home.
3. **⌘K (Ctrl K on non-Mac platforms) focuses the search box**, replacing `/`.
   The placeholder advertises the platform's key.

### Consequences
- Fewer entries means each section that remains on top reads as important;
  the price is one extra click for Scope, Glossary, ADRs and req42.
- The footer link row is now the only persistent path to `/req42`; if the
  footer is ever reworked, that link must survive.
- `/` is free again for the browser's quick-find. Users of the old shortcut
  need to learn one new key; the placeholder teaches it.
- `tests/test_home_layout.py` pins the nav list, the single brand on the home
  page, the footer links and the shortcut.
