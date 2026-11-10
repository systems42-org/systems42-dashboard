---
id: ISS-001
type: issue
title: Who holds the keys when two people work in parallel
status: open
created: 2026-11-10
updated: 2026-11-10
sources: ["[[SRC-002-grilling-session-on-stakeholders]]"]
related: ["[[STK-023-keyholder]]", "[[STK-007-workshop-facilitators]]", "[[STK-010-people-who-run-the-dashboard]]"]
tags: [issue]
severity: minor
kind: question
raised-by: Gernot Starke
resolved: null
---

# Who holds the keys when two people work in parallel

**What's unresolved.** How the Keyholder's rights and the name "Yoda" behave when two
people use the dashboard at the same time and the Keyholder closes their tab. The
Keyholder and Yoda concept also needs a fuller explanation. Gernot Starke deferred
both on purpose.

**Affects.** [[STK-023-keyholder]], [[STK-007-workshop-facilitators]],
[[STK-010-people-who-run-the-dashboard]].

**Context / evidence.**
- Gernot Starke expects the other person to become Yoda.
- The code (`app.py` at ed24d2e) passes the rights to the tab that connected
  next-earliest. That tab keeps its own nickname, so only the very first holder is
  ever called Yoda.
- [[STK-023-keyholder]] defines the Keyholder as the person who started the app. The
  code gives the rights to the first tab that connects. These are usually, but not
  always, the same.

**Options.**
1. Keep the code as it is and document it. "Yoda" names only the first holder.
2. Rename the new holder "Yoda", so the nickname follows the rights.
3. Tie the rights to whoever started the app, not to the first tab. This closes the
   gap between definition and code.

**Resolution.**
