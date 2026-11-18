---
type: metamodel
construct: notation
name: prose
aliases: [Prose]
title: Prose with acceptance criteria
summary: "Rules with exceptions or context that do not fit one EARS sentence, written as prose followed by acceptance criteria."
extends: functional-requirement
levels: [feature, requirement]
fields: []
anchors:
  - {name: acceptance-criteria, levels: [requirement]}
---

<!-- Capture: this file is the page template for `notation: prose`. Keep only the
     blocks whose `levels:` marker names the page's level, and drop the markers.
     Acceptance criteria are a checklist or Given/When/Then scenarios with
     concrete example data (FR-026). Prefer EARS where a rule fits one sentence. -->

# {{title}}

<!-- levels: feature, requirement -->
## Rationale

<why the requirement exists>

<!-- levels: feature, requirement -->
## Requirement

<the rule, with its context and exceptions>

<!-- levels: requirement -->
## Acceptance criteria

- [ ] <observable outcome with a concrete example>

<!-- levels: feature, requirement -->
## Hierarchy

- **Parent:** see `parent:`.
- **Children:** <finer requirements, or rely on `parent:` backlinks>

> [!note] Open points
> <ambiguities → raise as [[ISS-...]]>

<!-- levels: feature, requirement -->
## History

<!-- Optional, always last. -->
