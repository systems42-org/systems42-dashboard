---
type: anchor
title: arc42
aliases: [arc42, arc42-template]
tags: [anchor, framework, architecture]
applies-to: [architecture area, building blocks, deployment nodes, runtime scenarios, concepts, decision records]
---

# arc42

The template for communicating and documenting software architecture, by
**Dr. Peter Hruschka & Dr. Gernot Starke** (template V9, July 2025;
<https://arc42.org>, docs at <https://docs.arc42.org>). Twelve sections; this wiki
shares sections 1–3 and 9–12 with [[req42]] (the commons area) and implements
the architecture-only sections 4–8 one by one.

## Sections and where they live here

| arc42 | Here |
|-------|------|
| 1 Introduction & Goals | commons: goals, stakeholders; quality goals are quality requirements (C1) |
| 2 Constraints | commons C2 |
| 3 Context & Scope | commons C3 — one context for requirements and architecture; technical interfaces are external interfaces |
| 4 Solution Strategy | A1 (planned) |
| 5 Building Block View | **A2 — `building-block` pages** |
| 6 Runtime View | **A4 — `runtime-scenario` pages** |
| 7 Deployment View | **A3 — `deployment-node` pages** |
| 8 Crosscutting Concepts | **A5 — `concept` pages** |
| 9 Architecture Decisions | commons C7 — decision records with `kind: architecture` |
| 10 Quality Requirements | commons C1 |
| 11 Risks & Technical Debt | commons C6 (issues) |
| 12 Glossary | commons C5 |

## Building Block View (section 5) in short

- The **static decomposition** of the system into building blocks and their
  dependencies — the floor plan. Mandatory in every architecture documentation.
- A hierarchy of **black boxes** (what a block does: purpose/responsibility,
  interfaces, optionally quality characteristics, location, fulfilled
  requirements, open issues) and **white boxes** (what is inside a block: its
  parts, their dependencies, the motivation for the decomposition).
- **Level 1** is the white box of the whole system; level 2 zooms into selected
  level-1 blocks, and so on. Prefer relevance over completeness: describe the
  important, surprising, risky, complex or volatile blocks.

## Runtime, Deployment and Crosscutting Concepts (sections 6–8) in short

- **Runtime view:** a few concrete scenarios — important use cases, interactions
  at external interfaces, operation and error cases — as ordered steps between
  building blocks and their neighbours. Pick the important ones, not all.
- **Deployment view:** the technical infrastructure (environments, hosts,
  containers, services, channels) and the mapping of building blocks onto it.
  Levels as with blocks.
- **Crosscutting concepts:** practices, patterns, regulations and solution ideas
  that many blocks share — the basis of conceptual integrity. Pick only the
  most-needed topics.
- Here every page also carries `state: outdated | current | planned | target`
  (DR-010), so historical architecture stays on record.

## Checklist (advisory, during capture and inspect)

- Every block has a purpose sentence; every level-1 block has a `parent:` (or
  deliberately none).
- A block's `drivers:` name the requirements it answers; `decisions:` the records
  that shaped it.
- White boxes are not drawn by hand — they are projected from `parent:` and
  `uses:`.
- A runtime step between two blocks has a matching `uses:` edge (the dashboard
  flags misses on the scenario page).
- A page describing existing infrastructure says `state: current`; a replaced one
  names its successor in `superseded-by:` and becomes `outdated` once it is gone.
- A concept names what it `applies-to:` unless it really governs the whole system.
