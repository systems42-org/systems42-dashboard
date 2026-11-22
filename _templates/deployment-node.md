---
id: DN-NNN
type: deployment-node
title: <the node's name>
status: draft         # draft | review | accepted | deprecated
created: {{date}}
updated: {{date}}
sources: []
related: []
tags: [deployment-node]
stereotype:           # environment | host | container | service
parent:               # [[DN-...]] the enclosing node; empty = level 1
hosts: []             # [[BB-...]] deployed here
connects: []          # - {to: "[[DN-...]]", protocol: "HTTPS", note: "optional"} (also [[EIF-...]])
technology:           # optional: product, version, size
drivers: []           # [[QR-...]], [[CON-...]], … this node answers
decisions: []         # [[DR-...]] behind this node
state: target         # outdated | current | planned | target; empty = target
superseded-by:        # [[DN-...]] on a replaced page: its successor
---

# {{title}}

> follows [[arc42]] (section 7)

<!-- The deployment diagram is projected from `parent:`, `hosts:` and `connects:` — never draw it here. -->

## Purpose

<What this node is and why it exists, in one or two sentences.>
