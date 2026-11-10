---
name: requirements-wiki
description: >
  Build and maintain a software-systems requirements wiki using the Karpathy
  LLM-wiki pattern on an Obsidian vault. Use whenever the user wants to capture (ingest) a
  source (interview, transcript, spec, ticket) into requirements knowledge, inspect
  (audit) the wiki for contradictions/gaps/stale claims, report on requirements (open
  issues, coverage, stakeholder matrix, quality scenarios, traceability), or
  bootstrap a new requirements vault. Triggers: "capture this into the wiki", "ingest this",
  "inspect the wiki", "audit the requirements", "what open issues do we have", "requirements
  coverage", mentions of glossary/ubiquitous language, stakeholders/personas, use
  cases, epics/features/stories, quality requirements, constraints, building blocks, deployment, runtime scenarios, crosscutting concepts, current vs. target architecture, traceability from requirements to architecture. Content types:
  glossary term, goal, stakeholder, context, external interface, data model,
  activity model, use case, functional requirement (stereotype epic | feature |
  story), quality requirement, constraint, decision record, building block (arc42
  section 5; `drivers:` traces it to requirements), deployment node, runtime scenario,
  crosscutting concept (arc42 sections 7, 6, 8; `state: outdated | current | planned | target`), and issue
  (a first-class meta-type).
---

# Requirements Wiki

Operate a requirements knowledge base built on the Karpathy LLM-wiki pattern:
**compile knowledge once into a persistent, interlinked wiki and keep it current**,
rather than re-deriving from raw sources on every query.

## First: locate the vault and read its schema

1. Find the vault root (the directory containing `AGENTS.md`, `raw/`, `wiki/`,
   `_templates/`, `_system/`). Walk up from the working directory if needed.
2. **Read the vault's `AGENTS.md`** — it is authoritative for structure, content
   types, ID scheme, and conventions. This skill is the procedure; `AGENTS.md` is
   the data-specific schema. If they ever disagree, `AGENTS.md` wins.
3. Read the relevant procedure in `_system/workflows/` before running it.

If no vault exists and the user wants one, scaffold it: create the layer folders and
copy the canonical `_templates/` and `_system/anchors/` from an existing vault (or
recreate them from `AGENTS.md`'s schema), then write `AGENTS.md`, a `CLAUDE.md`
import, and `_system/`.

## Core discipline (applies to every operation)

- Apply `_system/anchors/` standards and cite them: goals via [[SMART]] or [[PAM]],
  stories via [[user-story-format]] + [[INVEST]], priorities via [[MoSCoW]].
  Enforcement is advisory — flag misfits as Issues, don't block or rewrite.
- One file per unit, ID `TYPE-NNN`, filename `TYPE-NNN-kebab-title.md`, frontmatter
  from the matching `_templates/` file. IDs are stable, never reused.
- Cross-reference with Obsidian wikilinks `[[FEAT-002-checkout]]` — never bare prose.
- Link every derived claim to its source in `sources:`.
- **Never silently resolve a contradiction or judgment call.** Raise an `ISS-NNN`
  Issue linking both sides and present options. Issues are a content type in
  `wiki/issues/` like any other; there is no standing dashboard — produce an
  open-issues report on demand.
- Keep `_system/index.md` and `_system/log.md` current. Log prefix is exact:
  `## [YYYY-MM-DD] <op> | <subject>`.

## Operations (full steps in `_system/workflows/`)

- **Capture** (formerly ingest) — source → typed pages. **Mandatory first:** activate the
  `grill-requirements` skill and stress-test the source before writing anything —
  capture is gated on this pass (see `_system/workflows/capture.md`). Then record
  provenance (`SRC-NNN` + sha256), read, discuss takeaways, extend-don't-duplicate,
  write pages, flag issues, update index, append log. Expect 8–15 pages touched.
- **Inspect** (formerly audit) — health-check: contradictions, stale claims, orphans, broken links,
  untestable quality requirements, unsourced claims, source drift, coverage gaps.
  Auto-fix only mechanical issues; queue judgment calls as Issues.
- **Report** — derive a view (open issues, coverage, stakeholder matrix, quality
  scenarios, glossary, traceability). File lasting reports back as wiki pages.

## Domain conventions

- **Language** (this project): wiki pages are English throughout; converse/ask in
  any language that suits the human. `_system/anchors/` and machinery are English too.
- Glossary = DDD ubiquitous language; one canonical meaning per bounded context.
- Quality requirements use ISO 25010 attributes + a Q42 quality scenario
  (source/stimulus/environment/response/**measure**). No measure ⇒ `testable: false`
  ⇒ Issue.
- Constraints follow arc42 categories (technical/organizational/legal/...).
- Stakeholders are simplified personas rated on influence × interest.
