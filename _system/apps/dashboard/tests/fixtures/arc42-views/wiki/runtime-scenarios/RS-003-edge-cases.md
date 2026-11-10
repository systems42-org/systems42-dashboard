---
id: RS-003
type: runtime-scenario
title: "Randfälle"
status: draft
created: 2026-10-19
updated: 2026-10-19
sources: []
related: []
tags: [runtime-scenario]
steps:
  - from: Box
    to: [[BB-003-console]]
    message: "Ticket #5 öffnen"
  - from: BB-003
    to: "[[BB-003-console]]"
    message: selbst
  - from: Web Browser
    to: Web-Browser
    message: weiter
  - from: Über
    to: Äöü
    message: Umlaute
  - "BB-001 ruft BB-002"
  - {from: "", to: Box, message: leer}
  - {from: TCP/IP Gateway, to: "[[BB-003-console]]", message: Weiterleitung}
drivers: []
decisions: []
state: target
superseded-by:
---

# Randfälle
