---
id: DN-002
type: deployment-node
title: "App-Server"
status: draft
created: 2026-10-19
updated: 2026-10-19
sources: []
related: []
tags: [deployment-node]
stereotype: host
parent: "[[DN-001-isaqb-cloud]]"
hosts: ["[[BB-003-console]]", "[[BB-004-account]]"]
connects:
  - {to: "[[DN-003-ldap]]", protocol: LDAPS, note: nur lesend}
  - {to: "[[EIF-001-mail]]", protocol: SMTP}
  - "[[DN-003-ldap]]"
  - {to: "[[DN-999-ghost]]", protocol: X}
  - {to: "[[DN-004-keycloak]]", protocol: OIDC}
technology: Ubuntu 24.04
drivers: []
decisions: []
state: current
superseded-by:
---

# App-Server

