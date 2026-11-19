---
id: STK-023
type: stakeholder
title: Keyholder
status: draft
created: 2026-11-10
updated: 2026-11-19
sources: ["[[SRC-001-stakeholders-of-the-systems42-dashboard]]", "[[SRC-002-grilling-session-on-stakeholders]]", "[[SRC-033-grilling-session-on-the-shared-session]]"]
related: ["[[STK-008-workshop-participants-and-facilitators]]", "[[STK-010-operators]]", "[[CON-001-proof-of-concept-not-production-ready]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[ISS-001-who-holds-the-keys-in-parallel-work]]", "[[FR-046-shared-session-in-a-workshop]]"]
tags: ["stakeholder"]
aliases: ["Jedi Master"]
role: Person who started the dashboard app
influence: low
interest: medium
provides: ["visibility settings", "end session"]
receives: ["wiki pages", "diagrams", "open issues"]
nature: person
context_role: Keyholder
---

# Keyholder

**Snapshot.** The person who started the dashboard app. Their browser tab holds the
dashboard's control rights. Only the Keyholder can save the visibility settings
(View) and end the session for everyone (Disconnect all).

**Goals.**
- Control one session: what is shown, and when it ends.

**Concerns / pains.**
- None recorded yet.

**How the rights pass.** The first tab to connect gets the rights and the nickname
"Yoda". When the holder's tab closes, the rights pass to the tab that connected
next-earliest. That tab keeps its own nickname. The README says the rights never go
back to an earlier holder. "The person who started the app" and "the first tab to
connect" are usually the same. Where they differ, the first tab holds the rights
([[ISS-001-who-holds-the-keys-in-parallel-work]], resolved). The session is described in [[FR-046-shared-session-in-a-workshop]].

**Not the facilitator.** The workshop facilitator ([[STK-008-workshop-participants-and-facilitators]]) leads the workshop and
holds the keys only if their tab connected first. Running the app ([[STK-010-operators]]) is
the usual way to become Keyholder.

**The name.** It replaces "facilitator" for this right. Rejected: Host (a
deployment-node stereotype), Owner (clashes with product owner), Admin and Moderator
(both suggest a login, and there is none). The alias "Jedi Master" is a joke. Yoda is
the Jedi Master in Star Wars. The first holder is called Yoda, but a later holder
keeps its own nickname, so "Jedi Master" names the role and "Yoda" only its first
holder.

**With a login.** If a login is added ([[CON-001-proof-of-concept-not-production-ready]]), the Keyholder becomes an identified
person instead of whoever connected first.

**Interactions.** None recorded yet.
