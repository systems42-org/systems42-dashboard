# Workflow: Inspect  (the "lint" / health-check pass)

Keep the wiki consistent, current, and complete. This workflow was called **audit**
until 2026-10; "inspect" is the Systems42 name for the same loop (see
[[GLO-004-inspect]] and [[ACT-002-inspect]]).

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
- **Missing pages** — concepts referenced but with no page (glossary terms used
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
- **Coverage gaps** — features with no stories/use-cases; stakeholders with no
  linked use-cases; use-cases with no acceptance path.
- **Context edges & projection** — the edges the context diagram is projected from
  (`EIF.flows`, `STK.provides`/`receives`) are the single source of truth.
  Check: every flow names an existing partner/role, the flows are mutually
  consistent, and `build_context_diagram()` renders valid mermaid. There is no
  drift by construction (a pure projection, nothing persisted) — so this is a
  consistency check only, not a redraw loop.
- **Relationship / graph edges** — reciprocal `related:`, concept-identity links across
  types (e.g. `GLO-` term ⇄ `DM-` entity of the same slug), entity ⇄ import-format. This
  is a structural check over the edge graph; run the dedicated **`relations.md`** (the
  graph linter) for it rather than inlining it here.

## Output
1. An **inspection report** presented in chat (or filed as a wiki page if lasting).
2. New/updated `ISS-NNN` for every finding worth tracking.
3. Auto-fix only high-confidence, mechanical issues (exact-match broken link to an
   existing page). Everything judgmental → queue as an Issue for the human.
4. Append to `_system/log.md`: `## [YYYY-MM-DD] inspect | <scope>` + finding counts.
