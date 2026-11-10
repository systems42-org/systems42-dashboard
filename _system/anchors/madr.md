---
type: anchor
title: MADR
aliases: [MADR]
tags: [anchor, decision-record]
applies-to: [decision-record]
---

# MADR

Markdown Any Decision Records — the record format for a
decision record (`DR-NNN`). MADR started as
"Markdown Architectural Decision Records" and extends Michael Nygard's
Context / Decision / Consequences with an explicit comparison of options.
Reference: <https://adr.github.io/madr/> (MADR 4.x).

**Shape.** Sections in this order; the first three are mandatory.

- **Context and Problem Statement** — the forces and the question to decide.
- **Considered Options** — the genuine alternatives, by name.
- **Decision Outcome** — the chosen option and why, with:
  - **Consequences** — good and bad; what becomes easier, what harder.
  - **Confirmation** *(optional)* — how compliance is checked: a review, a
    test, a checkable guardrail.
- **Decision Drivers** *(optional, before Considered Options)* — the forces
  that weigh most.
- **Pros and Cons of the Options** *(optional)* — per option, the arguments.
- **More Information** *(optional)* — links, follow-ups, amendments.

**People** *(all optional)*: `decision-makers` (who decided — names),
`consulted` (whose advice was sought), `informed` (who was told). MADR's own
`status` and `date` map onto the universal `status` and the `decided` field.

**What counts as a decision.** A record passes all three tests:

1. **Cross-cutting** — it shapes more than one requirement, content type or
   component.
2. **Expensive to reverse** — changing course later costs real migration or
   rework.
3. **A real choice** — genuine alternatives were weighed, and the record names
   them and their consequences.

A standing rule or wanted capability is a requirement (FR, QR, CON), even
when it was arrived at by deciding. Field additions, renames and naming
conventions are changelog entries.

## Checklist (inspect / grill)
- [ ] Passes all three tests; if not → propose filing it as a requirement or a changelog entry ([[ISS-...]]).
- [ ] Considered Options names at least two genuine alternatives (migrated records may say "Not recorded at the time").
- [ ] `kind` is set; `undefined` only when architecture vs. business is genuinely unclear.
- [ ] Consequences name a downside, not only benefits.
- [ ] A superseded record is `deprecated` and names its successor in `superseded-by`.
