---
type: metamodel
construct: notation
name: ears
aliases: [EARS]
title: EARS
summary: "Single functions or rules, each one sentence in one of the five EARS patterns."
extends: functional-requirement
levels: [feature, requirement]
implementable_levels: [requirement]
delivery_states: [implemented, outdated, removed]
fields: []
anchors: []
---

<!-- Capture: this file is the page template for `notation: ears`. Keep only the
     blocks whose `levels:` marker names the page's level, and drop the markers.
     The obligation (shall / should / may) is in the sentence; the priority stays
     in the separate MoSCoW field (FR-025). Prefer EARS over prose where it fits. -->

# {{title}}

<!-- levels: feature -->
## Summary

<the capability this group of EARS requirements covers>

<!-- levels: requirement -->
## Requirement

<While <precondition>, when <trigger>, the <system> shall <response>.>

<!-- levels: feature, requirement -->
## Rationale

<why the requirement exists>

<!-- levels: feature, requirement -->
## Hierarchy

- **Parent:** see `parent:`.
- **Children:** <finer requirements, or rely on `parent:` backlinks>

> [!note] Open points
> <ambiguities → raise as [[ISS-...]]>

<!-- levels: feature, requirement -->
## History

<!-- Optional, always last. -->
