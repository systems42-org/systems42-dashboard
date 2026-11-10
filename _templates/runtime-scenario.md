---
id: RS-NNN
type: runtime-scenario
title: <Was passiert, Verbphrase>
status: draft         # draft | review | accepted | deprecated
created: {{date}}
updated: {{date}}
sources: []
related: []           # [[GLO-...]] domain terms, [[ISS-...]]
tags: [runtime-scenario]
steps: []             # in order: - {from: "[[STK-...]]", to: "[[BB-...]]", message: "…", note: "optional"}
                      # from/to: [[BB-...]], [[EIF-...]], [[DN-...]] or [[STK-...]] (drawn as actor)
drivers: []           # [[UC-...]], [[ACT-...]], [[FR-...]], [[QR-...]], … this scenario realises
decisions: []         # [[DR-...]] behind this flow
state: target         # outdated (historical) | current (in use today) | planned (decided, not built) | target (end state); empty = target
superseded-by:        # [[RS-...]] on a replaced current-state page: its successor
---

# {{title}}

> follows [[arc42]] (section 6, runtime view)

<!-- The sequence diagram is projected from `steps:` by the dashboard — never
     draw it here. A step between two blocks without a `uses:` edge is flagged. -->

## Ablauf

<Optional. Was die Schritte nicht sagen: Auslöser, Besonderheiten, Fehlerfälle.>

## Offene Punkte

<Optional. [[ISS-...]] links.>
