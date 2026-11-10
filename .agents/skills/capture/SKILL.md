---
name: capture
description: >
  Use when the user runs `/capture`, says "capture <file>", "capture the new file in
  raw/", or otherwise asks to turn a source sitting in the `raw/` inbox (interview
  notes, transcript, spec, ticket, dictated loop definition) into typed wiki pages.
  Also use when a source has been dropped into `raw/` and nobody has captured it yet.
  Not for inspecting (auditing) the wiki, reporting, or bootstrapping an empty vault.
argument-hint: "[source file in the raw/ inbox, or empty to pick one]"
---

# /capture — run one Capture loop

Run the wiki's Capture loop ([[GLO-003-capture]], [[ACT-001-capture]]) on **one**
source from the `raw/` inbox. The procedure is `_system/workflows/capture.md`; this
skill only resolves the argument, enforces the gates, and hands over to it.

## 1. Resolve the source

`$ARGUMENTS` names the source. Accept a path, a bare filename, or a distinctive
fragment of the filename; match it against the top level of `raw/` (the inbox —
not `raw/ingested/`, `raw/sources/`, `raw/assets/`, `raw/examples/`).

| `$ARGUMENTS` | Do |
|---|---|
| matches exactly one inbox file | capture it |
| matches several | list the matches, ask which one |
| matches none / empty | list the inbox, ask which one — or, if there is exactly one file, propose it |
| names a file in `raw/ingested/` | stop: already captured; point at its `SRC-NNN` record |

Capture one source per run. If the human names several, run the loop once per
source, in the order given, and keep separate log entries.

## 2. Read the schema and the procedure — every time

1. Read the vault's `AGENTS.md` (schema, conventions, ID scheme).
2. Read `_system/workflows/capture.md` **in full** and follow its numbered steps.
3. Skim `_system/index.md` so you extend existing pages instead of duplicating.

## 3. The two gates (non-negotiable)

- **Before writing any page:** activate the `grill-requirements` skill and
  stress-test the source against the wiki. No page is written before this pass.
- **Before filing any Issue:** put the open questions to the human in one numbered
  round (the `grilling` skill, or plainly in chat if that skill is not available —
  say so). Only what the human leaves unanswered becomes an `ISS-NNN`.

## 4. Done means

The source has a `SRC-NNN` in `raw/sources/` with a sha256, the original is moved to
`raw/ingested/` with `origin:` updated, every page created or touched is in
`_system/index.md`, and `_system/log.md` has a `## [YYYY-MM-DD] capture | <title>`
entry.

Then report to the human, keeping these apart — never lump them under "still open":

- **Created** and **updated** pages.
- **Open decisions** — Issues with `status: open` this capture raised or touched.
  They are recorded; what is missing is the decision. Name who decides.
- **Parked follow-ups** — work deliberately deferred (e.g. schema changes waiting
  for an Issue), and the page where it is noted.
- **Not yet captured** — other sources still in the `raw/` inbox. Nothing about
  them is recorded yet; each needs its own capture run.

Say explicitly when the human answered every grilling question, so no Issues
were needed.

## Red flags

- You wrote a wiki page and have not run `grill-requirements` → stop, run it.
- Only `SRC-NNN` was created → you under-extracted (see the workflow's quality bar).
- An `ISS-NNN` exists for a question the human was never asked → convert it to a
  question first.
- You edited a file under `raw/` other than moving the original → revert; `raw/` is
  human-owned.
