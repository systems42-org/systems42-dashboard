# Workflow: Implement

Turn one directly implementable functional requirement, or one bounded use-case
slice, into a reviewed product change. The functional requirement remains the
source of intent; the implementation PR records the plan and evidence.

## The loop

1. **Select.** The human names one FR, or one use-case slice. Read that page,
   its parent/related pages, applicable constraints and quality requirements,
   and every open Issue linked to the selected scope.
2. **Check readiness.** List selected criteria, open Issues, and applicable
   quality requirements and constraints. Mark each blocking or non-blocking for
   this slice. A blocking question goes to [[ACT-003-clarify|Clarify]]; do not
   implement around it. A maturity value (`draft`, `review`, `accepted`) is not
   a gate. The human's explicit approval of the concrete plan is the gate.
3. **Plan.** Present a short summary first. For every selected criterion, name
   the intended files, implementation approach and check. State exclusions and
   non-blocking open points. Wait for the human's approval before changing any
   deliverable.
4. **Build.** Work on `implement/<id>-<slug>`. Every commit carries
   `Implements: FR-NNN` (for a use-case slice, include the slice name). Ask for
   renewed approval if the outcome changes: selected criteria, behaviour,
   dependencies, or removed behaviour. A different file list alone does not
   change the outcome; list the actual files in the PR.
5. **Check.** Walk each selected criterion and record `pass`, `fail`, or
   `not verified`, with specific evidence (test, command, or code review).
   Passing a test suite alone does not prove each criterion. Check prose,
   templates, workflows and other deliverables as deliberately as code.
6. **Record delivery.** Directly implementable pages may carry `delivery` and
   `delivery-checked`: those whose `level:` is in their notation's
   `implementable_levels` (Agile `story`, use-case `sea`/`fish`, EARS and prose
   `requirement`; the lint enforces it). Omit both fields on other levels, such
   as epics and features, and derive their progress from children. The values
   allowed are the notation's `delivery_states`. For an Agile story, set
   `implemented` only when all acceptance criteria pass; there is no `partial`
   story state. A use case is built in slices: set `partial` while any slice of
   the **whole use case** is still unbuilt, even when the selected slice is
   complete, and `implemented` only once every slice is (FR-031). Name the
   slice in commit trailers. Agile features and stories that refine a use case
   are part of its behaviour: the use case is `implemented` only when every
   refining story (also those under a refining feature) is `implemented`, so a
   run on the use case checks and records those stories too. The reverse does
   not hold: all stories done does not make the use case done. Use `outdated` when requirement content
   changed since its last checked baseline. Use `removed` only after its
   implementation has actually been removed. The timestamp is ISO 8601 with
   timezone. Git identifies the baseline as the latest committed change to a
   delivery field whose resulting state is `implemented` or `partial`; an
   `outdated` transition does not replace that baseline. A human-confirmed
   recheck that keeps the same active state updates the timestamp and creates a
   new baseline commit.
7. **Log and prepare one PR.** Append
   `## [YYYY-MM-DD] implement | FR-NNN <title>` to `_system/log.md`. The PR title
   names the requirement. Its description contains the approved plan and a
   criterion-by-criterion table with result and evidence, including anything
   not verified. Keep the human's review and merge as the final gate; this repo
   does not have branch protection enforcing that gate.
8. **Recheck before merge.** Update the branch from `main`, run
   `python3 _system/scripts/delivery.py FR-NNN` for every selected requirement,
   and recheck affected criteria if a requirement page changed on `main`.
   Resolve drift before asking for merge.

## Delivery fields and drift

- `delivery` is absent until a requirement has been checked by this loop.
- `delivery-checked` stores when the last successful human-confirmed check
  happened. Git history identifies the latest committed baseline that records
  `implemented` or `partial`; do not store a second commit hash on the
  requirement page. Automatically marking a page `outdated` preserves the
  previous active baseline.
- `delivery.py` compares the current requirement with the baseline version,
  ignoring those two metadata lines. Requirement-content drift sets
  `delivery: outdated` and prints a diff.
- A typo-only change still requires human review. Do not restore the previous
  delivery state or refresh the baseline until the human explicitly confirms
  that the change has no functional meaning.
- A repeated, successful check that reconfirms `implemented` or `partial` must
  update `delivery-checked`, so Git records a new baseline.

## Stop conditions

- Do not edit deliverables before the plan is approved.
- Do not implement around a blocking Issue.
- Do not claim a criterion passed without evidence; report `not verified`.
- Do not let the agent merge its own PR.
