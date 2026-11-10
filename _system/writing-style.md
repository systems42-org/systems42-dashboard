# Writing style

This guide is binding for every text written in this repository: wiki pages,
docs, decision records, changelog and log entries, commit messages and
dashboard UI text. It binds humans and agents alike.

The language, provenance and glossary rules in `AGENTS.md` stay in force; this
guide adds to them. Where a template prescribes a page's structure, the
template wins and these rules apply to the text inside it.

The guide applies to new and changed text. Do not rewrite existing text only
to bring it in line.

Goal: every text reads as written by a knowledgeable practitioner, and is
short enough that a human can review it completely.

## Reader

- Before writing, decide who reads this and what they will do with it.
- Assume a competent reader. Explain only what this reader does not know yet.

## Reviewability

- A human must review every page. Length is a cost the reviewer pays, so
  write the shortest text that is complete.
- One page, one unit. If a page covers two things, split it.
- State each fact once, in one place. Elsewhere, link to it with a wikilink
  instead of restating it.
- Write statements a reviewer can confirm or reject. "The export finishes
  within 5 seconds for 10,000 rows" is reviewable; "the export is fast" is not.
- A template section may stay empty. The wiki grows in iterations, so do not
  fill a section for the sake of filling it.
- When editing, change only what the change requires. Do not rephrase
  untouched text, so the diff shows exactly what to review.
- Suggested size: keep the body of a wiki page (frontmatter excluded) to
  about 300 words. This is a guide, not a limit. Decision records may run
  longer, because [[MADR]] asks for the alternatives and their consequences.

## Substance

- Start with the point: the conclusion, fact or instruction comes first.
  No windup, no commentary about the text itself.
- Every sentence carries information. If removing a sentence loses nothing,
  remove it.
- Be specific: names, numbers, versions, examples, consequences. An adjective
  must add checkable meaning ("3x faster", not "much faster").
- Describe what things do, how they work and what breaks.
- Take a position. For a trade-off, state the recommendation and the reason.
  Give competing views weight in proportion to their evidence.
- State uncertainty once, at the place it applies, and say what exactly is
  uncertain.
- Never invent sources, quotations or facts. Cite only sources that were
  actually checked; mark anything else `> [!assumption]` or raise an Issue.

## Wording

- Use the plain words practitioners use with each other. When two words fit,
  take the simpler one: "use", not "leverage"; "look into", not "delve".
- One term per concept. The glossary is canonical.
- Prefer literal statements. Use a comparison only when it explains faster
  than the literal version.
- Do not inflate. A tool is a tool and an update is an update, not a
  "milestone", a "transformation" or a "testament".
- Active voice with a named actor ("the scheduler retries the job").
- Address the reader directly where instructions are given.

## Structure

- Form follows content: prose for reasoning, lists for parallel items, tables
  for comparisons, headings only where a reader needs to navigate.
- List as many items as actually exist: two if there are two, five if five.
- Depth follows importance: three paragraphs for the hard point, one sentence
  for the minor one.
- Sentence length follows the thought: short for key statements, longer for
  connected reasoning.
- Punctuation is period, comma, colon and parentheses. No dashes or
  semicolons as sentence punctuation, except a semicolon between two short
  quoted examples.
- Stop when the content is complete. No recap, no closing paragraph unless it
  adds a next step.

## Voice

- Sound like a competent colleague: matter-of-fact, direct, relaxed.
- In docs and decision rationales, an opinion or a dry remark is welcome.
  Requirement and architecture pages state facts only.

## Final check

- Does the first sentence deliver the point?
- Can a reviewer read the whole text in one sitting and confirm or reject
  each statement?
- Could any paragraph appear unchanged in another text on the same topic?
  If yes, add the specifics that make it belong here, or cut it.
- Is every claim sourced, or marked as an assumption?

## Examples

| Instead of | Write |
|---|---|
| "It is not just a framework; it is a testament to modular design." | "The framework enforces strict separation between domain models and persistence layers." |
| "Furthermore, it is important to remember that testing ensures high quality." | "Run integration tests against real databases. Mocks hide query performance bugs." |
| "While critics argue X and proponents state Y, balance remains essential." | "For small teams, X is a waste of time. Adopt Y until you hit scale bottlenecks." |
