# Workflow: Capture

Turn one raw source into typed, interlinked wiki knowledge. This workflow was
called **ingest** until 2026-10; "capture" is the Systems42 name for the same
loop (see [[GLO-003-capture]] and [[ACT-001-capture]]).

## The loop in one breath

> Humans provide raw input and trigger the AI to fill the spec.
> 1. The input is transformed into clean, uniform markdown so the AI can process it.
> 2a. Input that fits one or more spec chapters is put into those sections and cross-linked.
> 2b. Input that does not fit becomes questions or Issues for a human to answer (→ clarify).

Steps 1–2 below realise loop step 1, steps 3–5 realise 2a, step 6 realises 2b.
Steps 7–9 are the bookkeeping that keeps the wiki navigable.

## Before you capture — mandatory: grill first

Every capture is **gated by a grilling pass.** Before writing any page from a new
source, activate the **grill-requirements** skill (load and follow
`.agents/skills/grill-requirements/SKILL.md`) and stress-test the material against
the existing wiki — sharpen the ubiquitous language, expose contradictions and
gaps, and let decisions crystallise. Only once the grilling has settled the shared
understanding do you proceed to the steps below. Do not skip this gate, even for
sources that look obvious.

**Two grills, and they are not the same one.** `grill-requirements` (this gate)
stress-tests the *material* against the wiki before you write anything.
**`grilling`** (step 6) interviews the *human* to settle the questions that
survive the writing. The first gates starting a capture; the second gates filing
an Issue.

**Language (this project):** You may grill and ask in any language. Every page
you write below is English throughout (see the Language convention in AGENTS.md).

## Steps

1. **Capture provenance.** Confirm the human's source file is in the `raw/` **inbox**
   (top level). Create a **slim** `SRC-NNN` provenance record from `_templates/source.md`
   — only frontmatter plus a one-line summary — in **`raw/sources/`**. Compute
   a body sha256 for drift detection (`shasum -a 256 <file>`); record it in frontmatter.
   Keep narrative out of the record; that belongs in `_system/log.md` (step 8).
2. **Normalise to clean markdown.** If the input is not already clean, uniform
   markdown — slides, audio, PDF, images, chat exports, mixed-language notes —
   transcribe it into plain markdown first so the extraction below works on text.
   The *original* stays untouched and is what the sha256 in step 1 hashes; the
   derived markdown is working material. Where a derived copy is kept is not yet
   decided — ask before inventing a location. Already-clean markdown: no-op.
3. **Read & discuss.** Read the source fully. Surface the key takeaways to the
   human *before* writing pages. Agree on emphasis.
4. **Extract by type.** For each piece of requirements knowledge, decide its type
   (glossary / goal / stakeholder / context / external-interface / data-model /
   activity-model / use-case / functional-requirement with `stereotype: epic | feature | story` /
   quality-requirement / constraint). Prefer extending an existing page
   over creating a near-duplicate — check `_system/index.md` first.
5. **Write / update pages.** Use the matching template. Assign the next free
   `TYPE-NNN`. Wikilink every cross-reference. If the page is the *same domain concept*
   as an existing page of another type (same slug/title — e.g. a `DM-` entity for an
   existing `GLO-` term), add the reciprocal `related:` link on **both** pages now
   (Tier 1 of `relations.md`, so the relationship inspection stays cleanup). Link the source
   in `sources:` and add the page to the source's `ingested-pages:`. Apply the relevant
   `_system/anchors/` standard (goal frame, story format/quality, priority) and
   cite it; flag conformance gaps as Issues per step 6.
6. **Ask first, then flag.** Every contradiction with existing content, gap,
   ambiguity, untestable quality requirement or missing stakeholder is a **question
   before it is an Issue.** Collect them all, then activate the **grilling**
   skill (Skill tool, `grilling`; the human starts the same interview with
   `/grill-me`) and put the whole frontier to the human in one numbered round,
   each question carrying your recommended answer. Look up anything the wiki
   can already answer yourself — finding facts is your job, deciding is theirs.

   Write whatever the human settles straight into the pages. Whatever they
   decline, defer, or cannot answer becomes an `ISS-NNN` linking both sides,
   exactly as before. **The gate is *try*, not *succeed*:** one round the human
   leaves unanswered is enough to fall back to Issues, so a capture never
   blocks on an open question.

   The skill ships with this repo, in `.agents/skills/grilling/`. If it is not
   among your available skills anyway, **say so plainly** and file the Issues
   without it. A missing skill is a loud fallback, never a silent one.

   Never silently overwrite a conflicting claim, and never pick a side on your
   own. A grilled answer is the human deciding; an ungrilled one is you
   guessing.
7. **Update index.** Add/adjust entries in `_system/index.md` under the right type heading.
   A decision record the session produced goes under **Decisions** like any other type.
   When a source gives the *reason* for a decision or a building block, fill its
   `drivers:` with the goals, use cases, FRs, QRs or constraints named — linked,
   not restated. Building blocks follow [[arc42]] section 5: one page per block,
   `parent:` for the level, `uses:` for dependencies. Deployment nodes (section 7),
   runtime scenarios (section 6) and crosscutting concepts (section 8) follow the
   same pattern. When a source describes **existing** infrastructure or software,
   set `state: current` (`outdated` if it is no longer in use, `planned` if it is
   decided but not built); naming its technology (Keycloak, LDAP, …) is allowed on
   architecture pages and, as a rule, not in requirements (DR-004 as amended by
   DR-010). Exceptions are allowed, because requirements and architecture share
   a grey zone (encryption, deployment and infrastructure technology), and a
   project whose subject is technology names it in its requirements. Fill
   `drivers:` only with reasons the source gives; an element whose reason nobody
   knows goes to the human as a question (archaeology), not a guess.
8. **Append to `_system/log.md`.** `## [YYYY-MM-DD] capture | <source title>` followed by a
   terse list of pages created/updated and issues raised.
9. **Archive the source.** Move the captured original from the `raw/` inbox
   to **`raw/ingested/`** and update the `SRC-NNN` `origin:` to its new path. This keeps
   the inbox to *un-captured* sources only; the file's content (and thus its sha256) is
   unchanged, so drift detection still resolves it via `origin:`. Sources with no file
   (e.g. a verbal interview) skip this. The folder keeps its historical name
   `ingested/` on purpose.

## Quality bar
A single capture commonly touches 8–15 pages. If it touched only the source record,
you under-extracted. If you created duplicates, you skipped step 4. If every open
question became an Issue without the human ever being asked, you skipped step 6.
