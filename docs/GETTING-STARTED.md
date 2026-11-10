# Getting Started — Capturing Requirements

A practical guide for a product owner who wants to start turning raw material —
interview notes, transcripts, specs, tickets — into a structured, living
requirements wiki. You curate and ask; the AI does the filing.

## The idea in one paragraph

You drop sources into a folder. You tell the AI to "capture" them. It reads each
one and builds interlinked pages — glossary terms, stakeholders, use cases, user
stories, features, quality requirements, constraints — and flags every open
question as an **Issue**. Nothing is re-derived from scratch later: the knowledge
is compiled once and kept current as you add more. You browse it in Obsidian.

## One-time setup (~5 minutes)

1. **Clone or download this repo.** You get one folder — the repo root — that is
   *both* your knowledge base and the AI's workspace.
2. **Open it in Obsidian** (Open folder as vault → pick the repo root). No
   plugins to install — you navigate with the built-in file list and **graph view**.
   The hidden `.claude/` folder won't show up in Obsidian.
3. **Point your AI agent at the same folder.** All harnesses use `AGENTS.md` for
   project rules. Claude Code reads `CLAUDE.md` as an import and discovers skills
   through `.claude/skills/` (symlinks to `.agents/skills/`).

4. **Run the bootstrap workflow once.** Tell the agent: **"Run the bootstrap
   workflow."** It names the vault (the shipped name is `Systems42`, the starter's
   own — replace it with yours), captures your vision as `GOAL-001`, and takes
   down the first glossary terms and your first stakeholder. Takes about 30
   minutes and gives the dashboard something to show.

That's it. You won't hand-write wiki pages beyond that, and there is nothing else
to configure — the AI creates and maintains every page itself.

## Your daily loop

### 1. Capture a source
Save anything worth keeping into the `raw/` folder: a meeting transcript, a
stakeholder email, a draft spec, a screenshot. (The Obsidian **Web Clipper**
extension saves web pages straight there.) These files are never edited — they're
your source of truth.

### 2. Capture it
Tell the agent: **"Capture the new file in raw/."**
It will read the source, talk through the key takeaways with you, then write or
update pages across the wiki — typically 8–15 of them — and raise Issues for
anything unclear. Watch it happen live in Obsidian's file list and graph view.

### 3. Review what it built
Open `_system/index.md` for the catalog, or use the **graph view** to see how everything
connects. Follow the links. If something's off, just tell the agent. Prefer a browser
to Obsidian? Run `./dashboard.sh` for a live, read-only view of the wiki —
handy for a quick check or for showing someone else without installing anything.
(That path needs Docker; `./dashboard.sh local` runs the same dashboard directly
with Python on `http://localhost:8000` instead.) In the dashboard, <kbd>⌘K</kbd>
(<kbd>Ctrl K</kbd> on Windows/Linux) jumps to search from any page. The dashboard follows the Systems42 sections
model: Requirements and Architecture as two areas, plus the Commons they share.
The ≡ menu holds Configure, Theme, Who's here, Help, Reload and Disconnect all;
Configure (facilitator only) hides sections you do not need, saved to the
hand-editable `_system/dashboard.yaml`. Hidden sections stay reachable by URL
and search.

### 4. Check what's still unknown
Ask **"Report open issues."** The AI reads the `wiki/issues/` folder and gives you
the current list of open questions, contradictions, and gaps — always up to date,
since it's generated fresh each time. This is your "what do we still need to nail
down?" view. **The AI never silently resolves an ambiguity — it asks you.** (You can
also just browse the `wiki/issues/` folder directly.)

### 5. When you're unsure, get grilled
Before committing to a feature or when a requirement feels fuzzy, say
**"Grill me on this."** The AI runs a focused interview — one question at a time,
each with its recommended answer — challenging your wording against the agreed
vocabulary, poking at edge cases, and pushing every goal toward a measurable form
and every "must-have" toward an honest priority. As answers firm up, it writes them
straight into the wiki and flags leftover questions as Issues. It's the fastest way
to turn a half-formed idea into clean, captured requirements.

### 6. Periodically, tidy up
Say **"Inspect the wiki."** It checks for contradictions, stale claims, orphaned
pages, broken links, untestable quality requirements, and goals or stories that
don't meet the quality bar — and queues anything needing your judgment as an Issue.

### 7. Report when you need a view
Ask for what you need, e.g.:
- *"Report open issues by severity."*
- *"Show requirements coverage"* (which features lack stories/use-cases).
- *"Give me the stakeholder matrix."*
- *"Trace this stakeholder's goals down to the user stories."*

## What gets captured (the content types)

| Type | What it holds |
|------|---------------|
| **Glossary** | The shared vocabulary — one agreed meaning per term. |
| **Stakeholder** | A simplified persona: goals, concerns, influence/interest. |
| **Data model** | Entities, attributes, relationships. |
| **Activity model** | A process: trigger → steps → outcome. |
| **Use case** | An actor's goal with main and alternate flows. |
| **Functional requirement** | A req42 functional requirement, stereotyped **epic / feature / story**, in an Epic→Feature→Story hierarchy (story format + acceptance criteria for stories). |
| **Quality requirement** | A measurable target (performance, security, …). |
| **Constraint** | A fixed limit on the solution. |
| **Issue** | An open question, contradiction, or gap — tracked until resolved. |

## A few good habits

- **Capture one source at a time** when starting out, and stay in the loop — you'll
  learn what the AI emphasizes and can steer it.
- **Don't pre-organize your sources.** Drop them in raw; let the AI do the filing.
- **Treat Issues as your to-do list.** When the open-issues board is empty, your
  requirements are as settled as your current sources allow.
- **It's just a git repo of markdown.** Commit often; you get full history and can
  branch for free.

## Where things live

```
.                        ← repo root = the vault; open this in both Obsidian and your AI agent
├── wiki/               ← the AI-maintained requirements (one folder per type)
├── raw/                ← you drop sources here (AI never edits these)
│   └── examples/       ← optional worked examples to seed a workshop
├── _templates/         ← page structures the AI follows when filing
├── _system/            ← workflows, anchors, index.md & log.md (bookkeeping)
│   ├── wiki.yaml       ← project identity (system name, tagline) read by the dashboard
│   ├── dashboard.yaml  ← dashboard settings (hide list)
│   ├── scripts/        ← new-project.sh (spawn / refresh another wiki) and friends
│   └── apps/dashboard/ ← the live dashboard (Flask)
├── docs/               ← this guide and other human documentation
├── .agents/skills/     ← canonical AI skills: capture, grill-requirements,
│                         requirements-wiki, new-project (hidden in Obsidian)
├── .claude/skills/     ← Claude Code compatibility symlinks to .agents/skills/
├── AGENTS.md           ← the shared schema and project rules
├── CLAUDE.md           ← Claude Code import of AGENTS.md
├── README.md           ← repo overview
├── CHANGELOG.md        ← what changed in the method, templates, skills and dashboard
├── Makefile            ← make dev / down / local (dashboard), make new / sync (projects)
└── dashboard.sh        ← starts the live, browsable dashboard (Docker)
```

Most of these are de-emphasized in Obsidian (see "Keeping the vault clean" below), so
day to day you mostly see `wiki/` and `raw/`.

You only ever *touch* `raw/`. Everything in `wiki/` is the AI's job.

## Keeping the vault clean

The repo ships with an Obsidian setting (in `.obsidian/app.json`) that **excludes**
the machinery — `_system/`, `_templates/`, `docs/`, `AGENTS.md`, `CLAUDE.md`, `README.md` — from
graph view, search, quick-switcher, and link autocomplete. So when you browse or
graph, you see requirements content, not bookkeeping. The `.claude/` skills folder is
hidden automatically (dot-folder).

These files still appear, greyed, in the left file-tree pane — Obsidian can't fully
hide them there without a plugin, and the repo deliberately uses none. If you want a
spotless tree, the community plugin *File Hider* will do it; otherwise the `_` prefix
keeps the machinery sorted together and out of your way.

To adjust what's excluded: Settings → Files and links → Excluded files.

## Starting another project (or starting over)

Don't wipe a vault to reuse it — spawn a fresh one next to it:

```
make new TARGET=../foo-shop NAME="Foo Shop" TAGLINE="Buy foo, fast."
```

(or tell the agent: *"start a new project"*). The new folder gets every method
file — `AGENTS.md`, templates, anchors, workflows, skills, dashboard, this guide
— and an empty `wiki/` and `raw/`, with its own name in `wiki.yaml` and an
initial git commit. It inherits no decision records: decisions are content, so
`wiki/decisions/` starts empty and the project's own decisions start at
`DR-001`. The method files state their rules themselves; the reasons behind
them stay with the vault you spawned from. Open it in Obsidian and Claude
Code and run the bootstrap workflow there. The vault you spawned it from is
untouched.

When you later fix a template or workflow in the original, push the fix into
the spawned project with `make sync TARGET=../foo-shop`. Sync refreshes method
files only; it never touches the project's pages (decision records
included), sources, or identity. Treat method files in a spawned project as read-only: fix at the
source, then sync.

A project spawned before decisions became wiki pages still keeps them in
`_system/adr/`, which the current dashboard no longer reads, so sync refuses
it. Run `make migrate-decisions TARGET=../foo-shop` once: the project's own
ADRs become `wiki/decisions/DR-NNN` with the same number (the inherited
ADR-0001 to 0003 are dropped, links and the index follow). Set each record's
`kind`, review and commit in the project, then sync.

**Bringing method changes back.** Sometimes the method has to grow inside a
project, because only real content shows what a new type or template should
look like. Do that work in the project in its own commits, message prefixed
`method:`, and bring it back with

```
make harvest TARGET=../foo-shop
```

run in the original. It writes `harvest-foo-shop-<date>.patch` there with
every difference on the method paths, lists the project's new `wiki/` folders
(a new content type needs its folder here, or the next `make new` lacks it)
and the project's decision records with the next free `DR-` number here.
Review the patch, `git apply --3way` it, add the folders, re-record any method
decision as a decision record here with its project origin, open a PR, and after the merge
`make sync` the project so both sides match again. Project pages never travel
this way; lessons that are not files go into the original's `raw/` inbox as a
source.

For a *partial* undo — one bad page rather than the whole vault — use
`git checkout -- <path>`.
