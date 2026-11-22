---
name: grill-requirements
description: >
  A grilling session that stress-tests a requirements plan, draft, or idea against
  the existing requirements wiki — sharpening the ubiquitous language, exposing
  contradictions and gaps, and updating wiki pages, Issues, and decision records inline as
  decisions crystallise. The agent MUST invoke this skill on its own before writing any
  wiki page from a new or changed source — every capture is grill-gated (AGENTS.md,
  `_system/workflows/capture.md`) — and SHOULD invoke it whenever requirements are being
  captured, refined, or pressure-tested. Also use when the user asks to pressure-test
  thinking ("grill me on this feature", "stress-test these requirements", "challenge my
  plan against what we know") or when capturing a source (interview, transcript, spec,
  ticket) into the wiki. Adapted from mattpocock/skills grill-with-docs for
  requirements engineering.
---

**When to invoke.** This skill is the capture gate, not just a user command. Before any
new or changed source becomes wiki pages, run it first to stress-test the material —
invoke it **on your own initiative, without waiting to be asked** — and also whenever a
requirement is being captured, refined, or challenged (AGENTS.md,
`_system/workflows/capture.md`). The user can still trigger it explicitly; you no longer
need them to.

Interview the user relentlessly about every aspect of this plan until you reach a
shared, precise understanding. Walk down each branch of the decision tree, resolving
dependencies between decisions one by one. For each question, provide your
recommended answer.

Ask the questions **one at a time**, waiting for feedback on each before continuing.

If a question can be answered by exploring the wiki or the `raw/` sources, explore
them instead of asking.

**Language (the **Language** convention in `AGENTS.md`):** The ubiquitous
language is English. You may grill and ask in **any language** — whatever flows
best with the human — but anything you write into the wiki (terms, requirements,
Issues, decision records) is captured **in English.**

## Orient first

Find the vault root (`AGENTS.md`, `raw/`, `wiki/`, `_templates/`, `_system/`). Read
`AGENTS.md` for the schema, skim `_system/index.md` for what already exists, and note the
`_system/anchors/` standards in play (SMART, PAM, user-story-format, INVEST, MoSCoW).
The wiki is your source of truth the way a codebase is for the original skill.

Create or update pages lazily — only when a decision has actually crystallised.

## During the session

### Challenge against the domain terminology
When the user uses a term that conflicts with `wiki/domain-terms/`, call it out
immediately. "Your glossary defines *cancellation* as X, but you seem to mean Y —
which is it?" If a needed term has no definition yet, propose one. Extend an existing term with a
stereotype and attributes when the domain needs that structure.

### Sharpen fuzzy language
When the user is vague or overloaded, propose a precise canonical term. "You say
*account* — do you mean the [[STK-...]] Customer or the User? Those are different."
Drive toward the ubiquitous language.

### Probe with concrete scenarios
Stress-test relationships and flows with specific, edge-case scenarios that force
precision about boundaries — exactly the cases a use case's alternate flows or a
data model's invariants must cover.

### Apply the anchors as a precision lens
- Goals: push for [[PAM]] (purpose/advantage/metric) or full [[SMART]]. "What's the
  metric that tells us this worked?"
- Stories: test against [[user-story-format]] and [[INVEST]] — real role? genuine
  benefit? testable? small enough?
- Quality requirements: demand a quantified measure — no measure means untestable.
- Priorities: challenge every `Must` against [[MoSCoW]]. "Does the release truly
  fail without this, or is it a Should?"

### Cross-reference against the wiki
When the user states how something works, check whether existing pages or `raw/`
sources agree. On contradiction, surface it and raise an `ISS-NNN` linking both
sides — do not pick a winner. "UC-007 says partial cancellation is allowed, but you
just said all-or-nothing — which is right?"

### Update the wiki inline
When a term, requirement, or decision resolves, capture it right then in the proper
typed page (per its template and anchors) — don't batch. Append the session's
touches to `_system/log.md`. Keep pages free of implementation detail; record only what is
meaningful at the requirements level.

Before editing a functional requirement with `delivery: implemented` or
`partial`, tell the human the edit will trigger an implementation drift warning.
Do not restore the old delivery state after a typo-only edit unless the human has
reviewed the diff and explicitly confirmed that the meaning is unchanged.

### Offer a decision record sparingly
Only offer a decision record (`wiki/decisions/`, `DR-NNN`, follows [[MADR]]) when
all three tests of the **Decisions** convention in `AGENTS.md` hold:
1. **Cross-cutting** — it shapes more than one requirement, content type or component.
2. **Expensive to reverse** — changing course later costs real migration or rework.
3. **A real choice** — genuine alternatives were weighed, and one was chosen for reasons.

If any is missing, skip it: a standing rule is a requirement, a field addition or
rename is a `CHANGELOG.md` entry. When unsure, ask. When you do write one, list it
under **Decisions** in `_system/index.md` like any other type.
