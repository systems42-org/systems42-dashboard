# Systems42 Dashboard: requirements wiki

This repository holds the **requirements** for the Systems42 dashboard: the
browsable, read-only view over a Systems42 requirements wiki. It is itself a
[Systems42](https://github.com/systems42-org) requirements wiki, structured along
[req42](https://req42.de), and it carries a copy of the dashboard it describes.
Everything here is written in English.

The dashboard code under `_system/apps/dashboard/` was copied from the iSAQB
atrium wiki, where it is developed. Here it is the subject of the requirements
and the viewer for them.

## The pattern

`raw/` holds the sources: notes, drafts, transcripts. They are dropped in and
never edited. `wiki/` holds the structured, interlinked requirements (glossary,
stakeholders, goals, requirements, decisions, issues and more), written from those
sources. `AGENTS.md`, `_templates/`, `_system/anchors/` and `_system/metamodel/`
define the content types and conventions.

## Quick start

1. `./dashboard.sh` (or `make dev`) starts the dashboard in Docker at
   `http://localhost:8080`. Without Docker, `./dashboard.sh local` runs it with
   Python at `http://localhost:8000`.
2. Open this folder in Obsidian with **Open folder as vault**.
3. Point your agent at this folder. `AGENTS.md` holds the rules; Claude Code reads
   it through `CLAUDE.md` and finds the skills in `.claude/skills/`.
4. To turn a file in `raw/` into wiki pages, ask for a capture
   (`_system/workflows/capture.md`).

For the full walkthrough, see [`docs/GETTING-STARTED.md`](docs/GETTING-STARTED.md).
What changed in the method: [`CHANGELOG.md`](CHANGELOG.md).
