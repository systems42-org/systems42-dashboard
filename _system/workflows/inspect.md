# Workflow: Inspect  (the "lint" / health-check pass)

Keep the wiki consistent, current, and complete. This workflow was called **audit**
until 2026-10; "inspect" is the Systems42 name for the same loop (see
[[DT-004-inspect]] and [[ACT-002-inspect]]).

## The loop in one breath

> Inspection is triggered automatically (after a capture, at fixed intervals) or
> explicitly by a human.
> 1. The content of the spec is checked against predefined rules / guardrails.
> 2. Every finding is added to the list of Issues for humans to clarify (→ clarify).

The **Checks** below are this wiki's guardrails (loop step 1); the **Output** section
realises loop step 2. Run after a capture, periodically, or on request.

## Checks

- **Contradictions** — claims that conflict across pages. Open an `ISS-NNN`
  (kind: contradiction) with both sides quoted; do not pick a winner.
- **Stale claims** — pages a newer source has superseded. Flag and propose update.
- **Orphans** — pages with no inbound wikilinks; decide link or deprecate.
- **Domain terms** — apply [[rule-structure-needs-stereotype]] and
  [[rule-one-term-per-meaning]]. Ask before changing a term’s classification.
- **Missing pages** — concepts referenced but with no page (domain terms used
  but undefined, stakeholders mentioned but not profiled).
- **Broken links** — wikilinks to nonexistent IDs.
- **Anchor conformance** — check instances against `_system/anchors/` checklists:
  goals not following [[SMART]]/[[PAM]], stories failing [[INVEST]] or the
  [[user-story-format]], priorities misusing [[MoSCoW]] (e.g. a mostly-`Must`
  hierarchy of functional requirements). Raise an Issue per misfit with the proposed fix; advisory, never auto-rewrite.
- **Untestable quality requirements** — any `QR-NNN` with `testable: false` or no
  quantified measure → Issue.
- **Unsourced claims** — assertions with empty `sources:` and no `> [!assumption]`.
- **Source drift** — recompute sha256 for each `SRC-NNN` against the file at its
  `origin:` path (archived sources live in `raw/ingested/`); mismatch means
  the raw file changed after capture → re-capture. A missing file at `origin:` is itself
  an Issue.
- **Requirement delivery drift** — run `python3 _system/scripts/delivery.py`.
  For pages with `delivery: implemented` or `partial`, compare the current FR
  with its latest committed active-delivery baseline while ignoring `delivery`
  and `delivery-checked`.
  Content changes set `delivery: outdated` and print a diff. Even a likely typo
  requires human review; only the human may confirm no functional change before
  the prior delivery value and a new check timestamp are restored.
  When a story that refines a use case is `outdated`, the check also lists the
  use case for a human recheck; it never changes the use case itself.
- **Notation conformance** — run `python3 _system/scripts/metamodel-lint.py`
  (known notation and level, declared and filled-in fields). Then compare each
  FR body with its notation file: every block marked for the page's level is
  present and filled in, and the notation's anchors for that level hold. For
  use cases: every main-flow step that can fail has an extension, and the
  minimal guarantee is stated (FR-024). Missing content is a finding, never a
  rewrite.
- **Coverage gaps** — Agile features with no stories; Cockburn use-case
  requirements with no acceptance path, primary actor or scope building block.
- **Context edges & projection** — the edges the context diagram is projected from
  (`EIF.flows`, `STK.provides`/`receives`) are the single source of truth.
  Check: every flow names an existing partner/role, the flows are mutually
  consistent, and `build_context_diagram()` renders valid mermaid. There is no
  drift by construction (a pure projection, nothing persisted) — so this is a
  consistency check only, not a redraw loop.
- **Relationship / graph edges** — reciprocal `related:`, concept-identity links across
  types (e.g. domain term ⇄ building block of the same slug), entity ⇄ import-format. This
  is a structural check over the edge graph; run the dedicated **`relations.md`** (the
  graph linter) for it rather than inlining it here.

## Output
1. An **inspection report** presented in chat (or filed as a wiki page if lasting).
2. New/updated `ISS-NNN` for every finding worth tracking.
3. Auto-fix only high-confidence, mechanical issues (exact-match broken link to an
   existing page). Everything judgmental → queue as an Issue for the human.
4. Append to `_system/log.md`: `## [YYYY-MM-DD] inspect | <scope>` + finding counts.
