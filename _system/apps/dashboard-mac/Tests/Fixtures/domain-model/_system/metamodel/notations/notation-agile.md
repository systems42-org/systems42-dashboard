---
type: metamodel
construct: notation
name: agile
aliases: [Agile]
title: Agile
summary: "Planning units for a team: epics and features name an outcome, stories are user stories with acceptance criteria. The fallback notation when nothing else is chosen."
extends: functional-requirement
levels: [epic, feature, story]
implementable_levels: [story]
delivery_states: [implemented, outdated, removed]
fields: []
anchors:
  - user-story-format
  - {name: INVEST, levels: [story]}
  - {name: acceptance-criteria, levels: [story]}
---

<!-- Capture: this file is the page template for `notation: agile`. Keep only
     the blocks whose `levels:` marker names the page's level, and drop the
     markers. Title grammar (convention A, [[story-mapping]]): epic/feature =
     noun phrase naming an outcome ("Season Preparation"); story = verb + object
     ("Cancel Entity"). The story map is a projection over these pages. -->

# {{title}}

<!-- levels: epic, feature, story -->
## Story

As a [[STK-...]] **&lt;role&gt;** I want **&lt;goal&gt;**, so that **&lt;benefit&gt;**.

<!-- levels: story -->
**Acceptance criteria.** > follows [[acceptance-criteria]]

- **Given** &lt;context&gt; **when** &lt;action&gt; **then** &lt;observable outcome&gt;.

<!-- levels: epic, feature -->
**PROBLEM / GOAL**

<the user and business problem this addresses>

<!-- levels: epic, feature -->
**Success metric(s).**

<how we know it worked, framed via [[PAM]] / [[SMART]]>

<!-- levels: epic, feature -->
**Scope.** in: <…> · out: <…>

<!-- levels: epic, feature, story -->
## Hierarchy

- **Parent:** see `parent:`.
- **Children:** <finer items, or rely on `parent:` backlinks>

> [!note] Open points
> <ambiguities, missing children, untestable criteria → raise as [[ISS-...]]>

<!-- levels: epic, feature, story -->
## History

<!-- Optional, always last: provenance and reframing notes as blockquotes. Omit
     the heading if there is nothing to record. -->
