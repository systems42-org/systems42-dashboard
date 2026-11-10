---
id: RS-001
type: runtime-scenario
title: "Zugangsdaten zurücksetzen (heute)"
status: draft
created: 2026-10-19
updated: 2026-10-19
sources: []
related: []
tags: [runtime-scenario]
steps:
  - {from: "[[STK-001-member]]", to: "[[BB-003-console]]", message: Passwort vergessen}
  - {from: "[[BB-003-console]]", to: "[[BB-004-account]]", message: Reset anfordern}
  - {from: "[[BB-004-account]]", to: "[[EIF-001-mail]]", message: 'Mail "Reset-Link"; senden', note: nach 5 Minuten ungültig}
  - {from: "[[BB-002-identity]]", to: "[[BB-004-account]]", message: Token prüfen}
  - {from: "[[BB-003-console]]", to: "[[BB-005-secrets]]", message: Hash speichern}
  - {from: "[[BB-004-account]]", to: "[[BB-999-ghost]]", message: Protokoll}
drivers: ["[[UC-001-reset-credentials]]", "[[ACT-001-self-service]]"]
decisions: []
state: current
superseded-by: "[[RS-002-reset-credentials-new]]"
---

# Zugangsdaten zurücksetzen (heute)

