---
name: new-project
description: >
  Use when the user runs `/new-project`, says "start a new project", "create a
  fresh wiki", "set up a validation project", "spawn a new vault from this one",
  wants to "sync the method" / "pull the latest templates" into a project that
  was created from this one, or wants to "bring method changes back" /
  "harvest the project" from one. Creates a fresh Systems42 requirements wiki
  that carries the product (schema, templates, anchors, workflows, skills,
  dashboard, docs) but none of this project's own requirements, or refreshes
  those product files in an existing one. Not for bootstrapping (naming,
  vision, first terms) — that happens inside the new project afterwards.
argument-hint: "[new <target-dir> --name \"<System>\" | sync <target-dir>]"
---

# /new-project — spawn or refresh a Systems42 wiki

The product and the project content live in one repository. This
skill is the boundary between them: it drives
`_system/scripts/new-project.sh`, which copies only the product allow-list and
never a wiki page, a raw source, or this project's identity.

## Which mode

- **`new`** — the user wants a fresh wiki for another system (a validation
  project, a client project, a workshop vault).
- **`sync`** — the user wants method fixes made *here* to reach a wiki that
  was created from here earlier.

If it is unclear, ask. Don't guess from the presence of a directory.

## `new` — create a fresh project

1. **Collect three things**, asking only for what the user has not said:
   - **System name** — the system whose requirements the new wiki will hold
     (not the client, not the team). Goes into `_system/wiki.yaml`.
   - **Tagline** — optional, one line under the name on the dashboard. Empty
     is fine; bootstrap can fill it later.
   - **Target directory** — must not exist or must be empty. If the user has no
     preference, propose a sibling of this repository named after the system in
     kebab-case, e.g. `../foo-shop`, and confirm before creating anything.
2. **Run the script** from this repository's root:
   ```
   _system/scripts/new-project.sh new <target-dir> --name "<System>" [--tagline "<line>"]
   ```
   It makes an initial git commit in the target. Pass `--no-git` only if the
   user says the target will live inside another repository.
3. **Read the script's output back** to the user: where the project is, that
   no decision records were taken over — decisions are content, the project
   numbers its own from DR-001 — and that `wiki/` and `raw/` are empty.
4. **Hand off.** Do **not** run the bootstrap workflow from here: the new
   folder's own `AGENTS.md` must drive it. Tell the user to open the new
   directory in Obsidian and Claude Code and say "Run the bootstrap workflow".
5. **Log it here.** Append to this repository's `_system/log.md`:
   `## [YYYY-MM-DD] new-project | <System>` with the target path and the commit
   it was created from. No index change — nothing in `wiki/` changed.

## `sync` — refresh method files in an existing project

1. **Confirm the target** was created from this repository (it has
   `_system/wiki.yaml`). The script refuses anything else. It also refuses a
   project that still has `_system/adr/` (spawned before decisions became
   wiki pages): run `_system/scripts/new-project.sh migrate-decisions
   <target-dir>` (or `make migrate-decisions TARGET=<dir>`) first, have the
   user set each new record's `kind`, review and commit in the target, then
   sync.
2. **Warn once** that `sync` overwrites `AGENTS.md`, `CLAUDE.md`, `_templates/`,
   `_system/anchors/`, `_system/workflows/`, `_system/scripts/`,
   `_system/apps/`, `README.md`, `Makefile`, `dashboard.sh`, `.gitignore` and
   `_system/README.md` in the target. Skills and docs the project added are
   kept; its `wiki/` (decision records included), `raw/`, `wiki.yaml`,
   `index.md` and `log.md` are never touched. If the user edited any of the overwritten
   files in the target, those edits are lost — the fix belongs here, then sync.
3. **Run** `_system/scripts/new-project.sh sync <target-dir>`.
4. **Tell the user to review and commit in the target**:
   `git -C <target-dir> status`. Do not commit there on their behalf.
5. **Log it here**: `## [YYYY-MM-DD] sync | <target>` with the commit synced from.

## Bringing method changes back (`harvest`)

Method work often has to happen *in* a project, where real content shows what
a new template or content type should look like. `harvest` is the way back.

1. **In the project, keep method work in its own commits**, message prefixed
   `method:` (a template, an anchor, a workflow, a skill, dashboard code, a
   new `wiki/<type>/` folder). Project pages never travel; only the product
   paths of the allow-list do.
2. **Run here** `_system/scripts/new-project.sh harvest <target-dir>` (or
   `make harvest TARGET=<dir>`). It writes `harvest-<project>-<date>.patch`
   into this repository (git-ignored) with every difference on the product
   paths, and prints two lists: `wiki/` folders the project has and this
   repository lacks, and the project's decision records with this
   repository's next free `DR-` number. It changes nothing else.
3. **Review the patch with the user** — a project README or changelog line
   that is project-specific does not belong here; drop those hunks. Then
   `git apply --3way <patch>`.
4. **Complete what a patch cannot carry**: `mkdir -p wiki/<type> && touch
   wiki/<type>/.gitkeep` for each new content type, its row in the
   `AGENTS.md` type table, its `_templates/` file and dashboard catalog entry
   if the patch did not bring them; re-record each *method* decision among the
   project's decision records here as a `DR-` under the next free number,
   citing the project record it came from (decisions about the project's own
   system stay there).
5. **Record the decision, open a PR** (`AGENTS.md` commit policy: schema changes go
   via PR), and after the merge **`sync` the project** so both sides match.
6. **Log it here**: `## [YYYY-MM-DD] harvest | <target>` naming the patch and
   what was taken.

## Rules

- **Method files are read-only in a spawned project — except as method work.**
  A quick fix to a template or workflow goes into the source project and
  `sync`s forward. Deliberate method development in a project (new content
  types, dashboard changes) is kept in `method:` commits and comes back with
  `harvest`; anything else drifts, and the Starter Kit never learns.
- **Findings about the method travel back as sources.** Friction met in a
  spawned project is raw material for *this* wiki: a notes file dropped into
  this repository's `raw/` inbox and captured like any other source.
  `harvest` carries files; sources carry the reasoning.
- **Never widen the allow-list ad hoc.** It lives at the top of
  `new-project.sh` and is tested by `_system/scripts/test-new-project.sh`.
  Shipping a new path amends the export decision; record it, don't just edit.
