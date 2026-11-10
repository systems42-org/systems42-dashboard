# Requirements Wiki — Agent Schema

You maintain a **software systems requirements wiki**. This file defines what the
wiki is, how it is structured, and the conventions you must follow. The detailed
*procedures* for operating it live in `_system/workflows/`. Read those before
running a workflow.

You own the `wiki/` layer entirely. The human owns `raw/`. You write; they curate.

## The three layers (Karpathy LLM-wiki pattern)

1. **`raw/`** — immutable sources: interview notes, transcripts, specs, emails,
   tickets, diagrams. You read these; you never edit them. Source of truth. Layout
   `raw/`'s **top level is the inbox** for *new, not-yet-captured*
   sources; once a source is captured its original is archived under
   **`raw/ingested/`**; the provenance records *you* author live in **`raw/sources/`**
   (Source type). All three hold human-owned originals or agent provenance —
   never silently edit a source file.
2. **`wiki/`** — the structured, interlinked requirements knowledge you generate
   and maintain. Every page is a typed content unit (see below).
3. **schema** — this file + `_templates/` + `_system/anchors/` + **`_system/metamodel/`**
   (the explicit metamodel: one page per type, relation, framework block and
   projection, with machine-readable frontmatter; `_system/scripts/metamodel-lint.py`
   checks templates and the dashboard catalog against it). Co-evolved
   with the human over time.

## Content types

Each lives in its own `wiki/<folder>/`, one file per unit, frontmatter per the
matching `_templates/` file. Never invent fields not in the template without a
`CHANGELOG.md` entry, and a decision record if the field changes a type's meaning
or a projection built on it (see *Decisions* below). The eighteen types:

| Type | Folder | Purpose |
|------|--------|---------|
| Glossary term | `wiki/glossary/` | Ubiquitous language. One canonical meaning per term, per bounded context. |
| Goal | `wiki/goals/` | req42 section 01 "Business Goals". One type, `stereotype: vision \| objective`; Vision = the overarching narrative, Objective = a [[PAM]] sub-goal with `beneficiary`/`metric`/`baseline`/`target`/`horizon`; hierarchy via `parent:`. |
| Stakeholder | `wiki/stakeholders/` | Simplified persona: goals, concerns, influence/interest. |
| Context (scope) | `wiki/context/` | System boundary: context diagram (projected from edges, never stored), in/out-of-scope (explicit non-goals), user roles ([[STK-...]]), external interfaces. req42 section 03. |
| External interface | `wiki/external-interfaces/` | Real external **systems** only, one neighbour per node: `partner` + a `flows:` list (data/direction/format/trigger). Human-actor channels live as `provides:`/`receives:` on the [[STK-...]] stakeholder, not as EIF. Referenced by the context node. |
| Data model | `wiki/data-models/` | Entities, attributes, relationships, source-of-truth, bounded context. |
| Activity model | `wiki/activity-models/` | Actor-driven process/workflow: trigger → steps → outcome. |
| Use case | `wiki/use-cases/` | req42 section 04: a functional requirement in use-case form, parallel to the FR type (DR-011). Actor goal: preconditions, main flow, alternates, postconditions; `goal:` lists the goals it serves; features and stories may refine it via `parent:`, its "Realized by" is projected from them. |
| Functional requirement | `wiki/functional-requirements/` | req42 block 04 "Functional Requirements" item (a *backlog* is a ranked projection over it, never stored); one type, `stereotype: epic \| feature \| story`. Epic→Feature→Story hierarchy via `parent:` wikilinks (graph-capable; a feature or story may also name a use case as parent), projected as a [[story-mapping\|story map]]; carries `order` + `priority` ([[MoSCoW]]) + `release`. Stories use [[user-story-format]] + [[acceptance-criteria]] + [[INVEST]]. |
| Quality requirement | `wiki/quality-requirements/` | ISO 25010 attribute + [[Q42]] quality scenario (source/stimulus/environment/response/measure, [quality.arc42.org](https://quality.arc42.org)). |
| Constraint | `wiki/constraints/` | Technical/organizational/legal limit on the solution space. |
| Building block | `wiki/building-blocks/` | arc42 section 5 (A2): one page per block as a black box; levels via `parent:` (empty or [[CTX-...]] = level 1), `uses:` dependencies, `drivers:` (the requirements it answers), `decisions:`. The white box is projected from the children, never drawn. Every architecture page (A2–A5) carries `state: outdated \| current \| planned \| target`, so historical architecture stays on record, and a replaced page names its successor in `superseded-by:` (DR-010). |
| Deployment node | `wiki/deployment-nodes/` | arc42 section 7 (A3): an infrastructure element, `stereotype: environment \| host \| container \| service`; levels via `parent:`, `hosts:` building blocks, `connects:` `{to, protocol}`, `technology`. The deployment diagram is projected: all states in one picture, each marked. |
| Runtime scenario | `wiki/runtime-scenarios/` | arc42 section 6 (A4): one concrete flow; ordered `steps:` `{from, to, message}` between blocks, external interfaces, nodes, stakeholders; `drivers:` the use cases / activity models it realises. The sequence diagram is projected. |
| Crosscutting concept | `wiki/concepts/` | arc42 section 8 (A5): a rule several blocks or nodes follow (identity, persistence, backup …); `category`, `applies-to:` (empty = whole system). |
| Decision record | `wiki/decisions/` | A choice among named alternatives that is cross-cutting and expensive to reverse; `kind: architecture \| business \| undefined`, shape per [[MADR]]; `drivers:` links the requirements it rests on. Not a home for standing rules (see *Decisions* below). |
| Issue (meta) | `wiki/issues/` | Open question / contradiction / gap. Cross-cuts every other type. |
| Source | `raw/sources/` | Slim provenance record (frontmatter + one summary line) for a captured source. |

## Semantic anchors

`_system/anchors/` holds reusable methodological standards — goal frames
([[SMART]], [[PAM]]), the [[user-story-format]], story quality ([[INVEST]]),
prioritization ([[MoSCoW]]), quality scenarios ([[Q42]]), decision records ([[MADR]]). They are method, not domain knowledge: authored,
stable, never captured. The umbrella anchor is **[[req42]]** — the requirements
framework whose sections the content types above implement (fuller reference
in `docs/req42/`); the other anchors are standards applied within its
sections. req42's chapters are called **req42 sections**, never "building blocks" —
that term is reserved for arc42. Cite them by alias from templates and instances rather than
restating their definitions. When you apply a standard, you may note it inline
(`> follows [[PAM]]`).

**Enforcement is advisory.** During capture and inspect, check instances against the
relevant anchor's checklist and raise an `ISS-NNN` for misfits (non-SMART goals,
stories failing [[INVEST]], a set of requirements that is mostly `Must`). Flag and propose —
never block or silently rewrite. The human decides.

## Conventions

- **Language** (this project): everything is English: titles, headings, body text,
  IDs, filenames, wikilink targets, frontmatter keys and values. Write plain,
  human English: no machine jargon, no marketing words. You may converse in any
  language the human prefers. `_system/`, `_templates/`, anchors, the metamodel
  and decision records are English as well.
- **Writing style**: `_system/writing-style.md` is binding for every text you
  write here: wiki pages, docs, decision records, changelog, log, commit
  messages. Read it before you write. Its first aim is text short enough for a
  human to review completely.
- **Grill before capture** (formerly "ingest"): Every capture is gated by a grilling pass. Before writing
  any page from a new source you **must** activate the `grill-requirements` skill
  to stress-test the material first. A second, different grill closes the capture:
  the `grilling` skill, aimed at the **human**, to answer the questions the
  writing threw up before any of them become Issues. See
  `_system/workflows/capture.md`.
- **IDs**: `TYPE-NNN`, e.g. `GLO-001`, `STK-003`, `UC-012`, `QR-004`, `ISS-009`.
  IDs are stable and never reused. Filenames: `TYPE-NNN-kebab-title.md`.
- **Links**: use Obsidian wikilinks `[[FEAT-002-checkout]]`. Every cross-reference
  is a real link so the graph view works. No bare prose references.
- **Frontmatter**: YAML, every page. `id, type, title, status, created, updated,
  sources, related, tags` are universal; type-specific fields per template.
- **Status lifecycle**: `draft → review → accepted → deprecated`. Issues use
  `open → in-progress → resolved → wontfix`.
- **Provenance**: every claim derived from a source links that source in
  `sources:`. If you state something with no source, raise an Issue or flag it
  inline as `> [!assumption]`.
- **Contradictions are not silently resolved.** When a new source conflicts with
  an existing page, raise an Issue (`ISS-NNN`), link both sides, and present the
  options to the human. Never pick a side on your own.
- **Decisions.** Record a choice as a decision record (`wiki/decisions/`,
  `DR-NNN`, follows [[MADR]]) only when it passes **all three** tests:
  (1) **cross-cutting** — it shapes more than one requirement, content type or
  component; (2) **expensive to reverse** — changing course later costs real
  migration or rework; (3) **a real choice** — genuine alternatives were weighed,
  and the record names them and their consequences. A standing rule or wanted
  capability is a **requirement** (FR, QR, CON), even when it was arrived at by
  deciding. Field additions, renames and naming conventions are **changelog**
  entries (`CHANGELOG.md`). A change that alters a content type's *meaning* or a
  projection built on it needs a decision record. When unsure, ask the human;
  never file a borderline case as a decision by default. Consult the existing
  decision records before changing a convention.
- **Issues are first-class, but ask before you file.** Any time you encounter an
  open question, ambiguity, missing stakeholder, untestable quality requirement,
  or orphaned reference, put it to the human first (`grilling`); an Issue is
  where a question goes when the human has *not* answered it, not the first
  place you take it. Issues are content units in `wiki/issues/` like any
  other type; there is no standing dashboard — ask for an open-issues report when
  you want the current view.

## Commit policy

The `status` field carries a page's maturity, so a commit to `main` does not mean
"agreed". Delivery follows the status the content is entering. Keep one commit per
capture or inspect run, with a message naming it, so `git revert` stays clean; the
`_system/log.md` entry is the review trail.

| Change | Delivery |
|--------|----------|
| New or edited `wiki/` pages at `draft` or `review` | Commit to `main` |
| Raising an Issue | Commit to `main` |
| Resolving an Issue (`resolved`, `wontfix`) | Commit to `main`; PR only if it also promotes content to `accepted` or changes the schema |
| Promoting a page to `accepted`, or demoting to `deprecated` | **PR** — only the human promotes; you never merge your own promotion |
| Substantive edit to an `accepted` page | Set it back to `review` and commit to `main`, or open a PR |
| `CLAUDE.md`, `_templates/`, `_system/` (workflows, anchors, scripts, apps) | **PR** |
| `raw/` | Outside this policy — human-owned |

Review of `draft` content happens in the grilling passes and by status promotion,
not in a PR. Anything that reads `main` (reports, exports) must filter on `status`.

## Cold start

If `_system/wiki.yaml` is still blank and the wiki is otherwise empty, run
`_system/workflows/bootstrap.md` first — the first-30-minutes procedure that
names the system, seeds a vision, and captures the first terms and
stakeholder. It is deliberately **not** grill-gated (see that file). Once
bootstrap hands off, proceed with `capture.md` as normal.

## Files you maintain

- **`_system/index.md`** — content catalog, grouped by type, one line each. Update
  on every capture. Decision records are listed under **Decisions** like any other
  type.
- **`_system/log.md`** — append-only. Every capture / inspect / report appends one
  entry with the prefix `## [YYYY-MM-DD] <op> | <subject>` so it stays greppable.

## Operating principle

The human curates sources, asks questions, and decides. You do the bookkeeping:
summarizing, typing, cross-referencing, filing, flagging contradictions, keeping
the index and log current. A single capture typically touches 8–15 pages.
Stay disciplined; the value of this wiki is that the maintenance cost is near zero.
