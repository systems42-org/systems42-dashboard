---
id: UC-NNN
type: use-case
title: <Goal as actor intent — verb + object>   # naming convention A, see [[story-mapping]]
status: draft
created: {{date}}
updated: {{date}}
sources: []
related: []
tags: [use-case]
primary-actor: <[[STK-...]]>
level: user-goal     # summary | user-goal | subfunction
priority: should     # [[MoSCoW]]: must | should | could | wont
goal: []             # goals served: ["[[GOAL-...]]", ...] (0..*, DR-011)
---

# {{title}}

**Primary actor.** <[[STK-...]]>
**Supporting actors.** <[[STK-...]], [[EIF-...]] external systems>
**Goal.** <single sentence, from the primary actor's perspective>

**Stakeholders & interests.**
- <[[STK-...]]> — <what they need from this use case>

**Preconditions.**
- <must hold before>

**Trigger.** <the event that starts it>

**Main flow.**
1. <actor action / system response>
2. <...>

**Alternate / exception flows.**
- *A1.* <condition> → <branch>

**Postconditions.**
- Success: <guaranteed end state>
- Minimal: <guarantee even on failure>

**Special requirements.** <non-functional notes tied to this UC → [[QR-...]], [[CON-...]]>

**Realized by.** projected from the features and stories whose `parent:` names this use case (DR-011); add prose here only for context.

> [!note] Open points
> <ambiguities → raise as [[ISS-...]]>
