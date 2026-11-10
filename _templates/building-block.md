---
id: BB-NNN
type: building-block
title: <Block name>
status: draft         # draft | review | accepted | deprecated
created: {{date}}
updated: {{date}}
sources: []
related: []           # [[GLO-...]] the domain terms this block implements, [[ISS-...]]
tags: [building-block]
parent:               # [[BB-...]] the enclosing block; empty or [[CTX-...]] = level 1
drivers: []           # [[GOAL-...]], [[UC-...]], [[FR-...]], [[QR-...]], [[CON-...]] this block answers
decisions: []         # [[DR-...]] that shaped this block
uses: []              # [[BB-...]] / [[EIF-...]] it depends on (arrows of the white box)
location:             # optional: directory / module / package in the code
state: target         # outdated (historical) | current (in use today) | planned (decided, not built) | target (end state); empty = target
superseded-by:        # [[BB-...]] on a replaced current-state page: its successor
---

# {{title}}

> follows [[arc42]] (section 5, black box)

<!-- One page per building block. The white box (children + their `uses:` arrows)
     is projected by the dashboard from the children's `parent:` — never draw it
     here. Prefer relevance over completeness. -->

## Purpose / Responsibility

<What this block does, in one or two sentences.>

## Interfaces

<What it offers and needs, unless covered by `uses:` and the neighbours' pages.>

## Quality / Performance

<Optional. Characteristics this block must deliver; the QRs belong in `drivers:`.>

## Open issues

<Optional. [[ISS-...]] links.>
