# Workflow: Capture

Turn one raw source into typed, interlinked wiki knowledge. This workflow was
called **ingest** until 2026-10; "capture" is the Systems42 name for the same
loop (see [[DT-003-capture]] and [[ACT-001-capture]]).

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

**Two passes, and they are not the same one.** `grill-requirements` (this gate)
stress-tests the *material* against the wiki before you write anything. The
**closing round** (step 6) asks the *human* the questions that survive the
writing. The first gates starting a capture; the second gates filing an Issue.

**Language:** The ubiquitous language is English (see the **Language**
convention in `AGENTS.md`). You may grill and ask in any
language, but every page you write below is captured **in English.**

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
   (domain-term / goal / stakeholder / context / external-interface /
   activity-model / functional-requirement with `notation:` and `level:` /
   quality-requirement / constraint / building-block / solution-strategy /
   runtime-scenario / deployment-node / crosscutting-concept). Prefer extending an existing page
   over creating a near-duplicate — check `_system/index.md` first.
5. **Write / update pages.** Use the matching template. Assign the next free
   `TYPE-NNN`: one above the highest ID ever used, never a retired one of this wiki
   (retirements are named in `_system/log.md`, so the highest page on disk may not be the highest used). Wikilink every cross-reference. Add a stereotype and structure to an
   existing domain term when needed. Keep one term page per meaning and context. If the page is the *same domain concept*
   as an existing page of another type (same slug/title — e.g. a building block that implements an
   existing domain term), add the reciprocal `related:` link on **both** pages now
   (Tier 1 of `relations.md`, so the relationship inspection stays cleanup). Link the source
   in `sources:` and add the page to the source's `ingested-pages:`. Apply the relevant
   `_system/anchors/` standard (goal frame, story format/quality, priority) and
   cite it; flag conformance gaps as Issues per step 6.
   A **functional requirement** takes its notation in this order: one the human
   chose explicitly for it; else `default_notation` in `_system/wiki.yaml`; else
   `agile` (FR-004, FR-023). Building-block defaults (FR-019) are not configurable
   yet; when the human names one, treat it as an explicit choice. Store the result
   in `notation:` and never change it later without asking. The page is the shared
   frontmatter of `_templates/functional-requirement.md` plus the body of the
   notation file (`_system/metamodel/notations/notation-<name>.md`, or
   `_system/notations/<name>.md` for a project notation), keeping only the
   blocks whose `levels:` marker names the page's `level:`. Set
   `building-blocks:` to the blocks the requirement concerns (FR-005).
   Before changing an FR with `delivery: implemented` or `partial`, tell the
   human that this edit makes its implementation claim subject to a drift check.
   After the edit, Inspect marks it `outdated`; do not restore its former value
   without the human's explicit confirmation that the meaning did not change.
6. **Ask first, then flag.** Every contradiction with existing content, gap,
   ambiguity, untestable quality goal or missing stakeholder is a **question
   before it is an Issue.** Collect them all and put them to the human in a
   **closing round**:

   - **One message, every question that can be asked now.** Number them. Each
     names the page or claim it concerns, lays out the options where there
     are any, and ends with the answer you recommend and why.
   - **Hold back what depends on another open answer.** A question that only
     makes sense once a different one is settled waits for the next round;
     asking it now forces the human to guess.
   - **Look facts up yourself.** Anything the wiki, the sources or the
     repository can answer is not a question. Finding facts is your job;
     deciding is the human's.
   - **Then wait, and go again.** Settled answers often unlock new questions;
     ask those in the next round. Stop when nothing is left to ask.

   A round looks like this:

   ```
   **Q1 — <short title>** (<page or claim>)
   <the question, with the options if there are any>
   → Recommended: <answer>, because <reason>.

   **Q2 — …**
   ```

   Write whatever the human settles straight into the pages. Whatever they
   decline, defer, or cannot answer becomes an `ISS-NNN` linking both sides,
   exactly as before. **The gate is *try*, not *succeed*:** one round the human
   leaves unanswered is enough to fall back to Issues, so a capture never
   blocks on an open question.

   A **recovery report** from [[ACT-005-recover|Recover]] arrives with its gaps
   marked answered or open. Ask its open gaps in this round, or file them as
   Issues; the report itself is not edited.

   Never silently overwrite a conflicting claim, and never pick a side on your
   own. An answered question is the human deciding; an unasked one is you
   guessing.
7. **Update index.** Add/adjust entries in `_system/index.md` under the right type heading.
   A decision record the session produced goes under **Decisions** like any other type.
   When a source gives the *reason* for a decision or a building block, fill its
   `drivers:` with the goals, use cases, FRs, QRs or constraints named — linked,
   not restated. Building blocks follow [[arc42]] section 5: one page per block,
   `parent:` for the level, `uses:` for dependencies.
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
