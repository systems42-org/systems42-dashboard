---
type: anchor
title: arc42
aliases: [arc42, arc42-template]
tags: [anchor, framework, architecture]
applies-to: [architecture area, building blocks, decision records]
---

# arc42

The template for communicating and documenting software architecture, by
**Dr. Peter Hruschka & Dr. Gernot Starke** (template V9, July 2025;
<https://arc42.org>, docs at <https://docs.arc42.org>). Twelve sections; this wiki
shares sections 1–3 and 9–12 with [[req42]] (the commons area) and implements
the architecture-only sections 4–8 as one content type each.

## Sections and where they live here

| arc42 | Here |
|-------|------|
| 1 Introduction & Goals | commons: goals, quality goals, stakeholders |
| 2 Constraints | commons C2 |
| 3 Context & Scope | commons C3 — one context for requirements and architecture; technical interfaces are external interfaces |
| 4 Solution Strategy | A1 — `solution-strategy` pages |
| 5 Building Block View | **A2 — `building-block` pages** |
| 6 Runtime View | A4 — `runtime-scenario` pages |
| 7 Deployment View | A3 — `deployment-node` pages |
| 8 Crosscutting Concepts | A5 — `crosscutting-concept` pages |
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

## Sections 4, 6, 7 and 8 in short

- **Solution strategy (4):** a short, motivated summary of the fundamental
  decisions; links the decision records, never restates them.
- **Runtime scenario (6):** how the parts interact for one architecturally
  relevant scenario; structured `steps:`, the sequence diagram is projected;
  links the FR or activity model it `realizes:`.
- **Deployment node (7):** an infrastructure element (environment, host,
  container, service); levels via `parent:`, software mapping via `hosts:`,
  channels with protocol via `connects:`.
- **Crosscutting concept (8):** a practice applied across blocks and nodes
  (logging, error handling, …); choices stay decision records, limits stay
  constraints.
- **State:** every architecture page says whether it is `outdated`, `current`,
  `planned` or `target` (empty = target); `superseded-by:` links a replaced page
  to its successor. `status` stays the page's maturity.

## Checklist (advisory, during capture and inspect)

- Every block has a purpose sentence; every level-1 block has a `parent:` (or
  deliberately none).
- A block's `drivers:` name the requirements it answers; `decisions:` the records
  that shaped it.
- White boxes are not drawn by hand — they are projected from `parent:` and
  `uses:`.
