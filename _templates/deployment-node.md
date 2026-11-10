---
id: DN-NNN
type: deployment-node
title: <Name des Knotens>
status: draft         # draft | review | accepted | deprecated
created: {{date}}
updated: {{date}}
sources: []
related: []           # [[GLO-...]], [[ISS-...]]
tags: [deployment-node]
stereotype:           # environment | host | container | service
parent:               # [[DN-...]] the enclosing node; empty = level 1
hosts: []             # [[BB-...]] deployed on this node
connects: []          # - {to: "[[DN-...]]", protocol: "LDAPS", note: "optional"} (also [[EIF-...]])
technology:           # optional: product, version, size (e.g. Keycloak 26, Hetzner CX32)
drivers: []           # [[GOAL-...]], [[UC-...]], [[FR-...]], [[QR-...]], [[CON-...]] this node answers
decisions: []         # [[DR-...]] behind this node
state: target         # outdated (historical) | current (in use today) | planned (decided, not built) | target (end state); empty = target
superseded-by:        # [[DN-...]] on a replaced current-state page: its successor
---

# {{title}}

> follows [[arc42]] (section 7, deployment view)

<!-- The deployment diagram is projected from `parent:`, `hosts:` and
     `connects:` — never draw it here. -->

## Zweck

<Wofür es diesen Knoten gibt.>

## Betrieb

<Optional. Größe, Standort, Verantwortliche, Besonderheiten.>

## Offene Punkte

<Optional. [[ISS-...]] links.>
