---
type: metamodel
construct: notation
name: use-case
aliases: [Cockburn, "Use case"]
title: Cockburn use case
summary: "Multi-step interactions with failure paths, written as Cockburn-style use cases on the goal levels kite, sea and fish."
extends: functional-requirement
levels: [kite, sea, fish]
fields:
  - {name: primary-actor, kind: link, relation: primary-actor, required: true, doc: "stakeholder whose goal the use case is"}
  - {name: scope-building-block, kind: link, relation: scope-building-block, required: true, doc: "exactly one building block, or the context for a whole-system use case (FR-005)"}
anchors:
  - {name: acceptance-criteria, levels: [sea, fish]}
---

<!-- Capture: this file is the page template for `notation: use-case`. Keep only
     the blocks whose `levels:` marker names the page's level, and drop the
     markers. Title: the primary actor's goal as verb + object. For every
     main-flow step ask "what can go wrong here?" (FR-024); a step without an
     extension needs the human's answer before the page is written. New pages
     get `FR-NNN` IDs; migrated use cases keep their `UC-NNN` IDs. -->

# {{title}}

<!-- levels: kite, sea, fish -->
## Goal

**Primary actor.** see `primary-actor:` · **Supporting actors.** <[[STK-...]], [[EIF-...]]>
**Scope.** see `scope-building-block:` · **Goal.** <one sentence, from the primary actor's perspective>

<!-- levels: kite, sea, fish -->
## Rationale

<why the primary actor and the business need this outcome>

<!-- levels: kite, sea, fish -->
## Stakeholders & interests

- <[[STK-...]]> — <what they need from this use case>

<!-- levels: sea, fish -->
## Preconditions

- <must hold before the trigger>

<!-- levels: sea, fish -->
## Trigger

<the event that starts the use case>

<!-- levels: kite, sea, fish -->
## Main flow

1. <actor action / system response>
2. <…>

<!-- levels: sea, fish -->
## Extensions

<!-- One entry per main-flow step that can fail, numbered after the step. -->
- *1a.* <condition> → <handling, and where the flow resumes or ends>

<!-- levels: kite, sea, fish -->
## Minimal guarantee

<what holds even when the goal fails>

<!-- levels: kite, sea, fish -->
## Success guarantee

<the end state when the goal succeeds>

<!-- levels: sea, fish -->
## Special requirements

<quality requirements and constraints tied to this use case → [[QR-...]], [[CON-...]]>

<!-- levels: kite, sea, fish -->
## Hierarchy

- **Parent:** see `parent:`.
- **Children:** <lower-level use cases, or rely on `parent:` backlinks; at sea and fish level, Agile features and stories may also refine this use case (the dashboard lists them under "Realized by")>

> [!note] Open points
> <ambiguities, steps without extensions → raise as [[ISS-...]]>

<!-- levels: kite, sea, fish -->
## History

<!-- Optional, always last. -->
