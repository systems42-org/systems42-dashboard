---
id: DR-006
type: decision-record
title: Interactive diagrams are projected on the server and laid out in the browser
status: draft
created: 2026-11-19
updated: 2026-11-19
sources: ["[[SRC-034-dashboard-requirements-moved-from-meta]]", "[[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]"]
related: ["[[FR-040-two-views-of-the-same-terms]]", "[[FR-047-see-the-requirements-as-a-story-map]]", "[[FR-051-reveal-related-page-types-layer-by-layer]]", "[[QR-001-usable-on-phone-and-tablet]]"]
tags: [decision-record]
aliases: []
kind: architecture
decided: 2026-11-19
decision-makers: [Peter Gerstbach]
consulted: [Claude]
informed: []
drivers: ["[[FR-040-two-views-of-the-same-terms]]", "[[FR-047-see-the-requirements-as-a-story-map]]"]
amends: []
superseded-by: []
---

# Interactive diagrams are projected on the server and laid out in the browser

> follows [[MADR]]

## Context and Problem Statement

Until the term network, every diagram of the dashboard was a Mermaid string, drawn by the server from the wiki's typed links. A network that reads as alive, one that clusters and can be dragged and filtered, needs a physics layout, and Mermaid lays out only hierarchies. The term network ([[FR-040-two-views-of-the-same-terms]], [[FR-051-reveal-related-page-types-layer-by-layer]]) and the detail diagram of the story map ([[FR-047-see-the-requirements-as-a-story-map]]) both need it.

How do the dashboard's interactive diagrams get their data and their layout?

## Decision Drivers

- The audience of the dashboard has no Obsidian ([[GOAL-003-answers-without-asking-a-colleague]]).
- A diagram must stay testable: the same wiki gives the same data every time.
- Every node must stay reachable as a text link on a phone ([[QR-001-usable-on-phone-and-tablet]]).

## Considered Options

1. **Mermaid only.** The server draws every diagram. No physics layout, no filtering, no clustering.
2. **The Obsidian graph.** Needs Obsidian, which the audience does not have.
3. **Projection on the server, layout in the browser.** The server projects the diagram's data as JSON from the typed links, the same way it projects Mermaid. A script in the browser only arranges and styles it.

## Decision Outcome

Chosen option: **3**, because it is the only one that gives an interactive network to readers without Obsidian and keeps the data deterministic and testable. Mermaid stays for static diagrams, such as the context diagram, the data model, the goals diagram and the breakdown of a requirement.

The library that does the arranging is a detail of the code and can change without changing this decision.

### Consequences

- Good: one source of truth. The projection is a pure function of the wiki and is tested like the Mermaid ones.
- Good: every interactive diagram can offer its nodes as text links beside the picture.
- Good: the pattern already carries the page that shows the metamodel, besides the term network.
- Bad: the arrangement differs from one load to the next, so two screenshots of the same network are not identical.
- Bad: the dashboard needs a script library that it vendors, next to Mermaid, to work offline.
- Bad: two ways of drawing exist, and a new diagram needs a choice between them.

## More Information

The reasoning behind it, with the weighing of the three options and the later amendments on layout and readability, is in the Systems42 method wiki ([meta DR-023](https://github.com/systems42-org/meta/blob/main/wiki/decisions/DR-023-glossary-term-network-force-graph.md)), where it was recorded for the term network alone.
