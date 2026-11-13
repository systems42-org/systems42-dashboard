# Help

## Reading this dashboard

**Three areas, two levels.** The home page shows **Requirements** and
**Architecture** as two peaks and **Commons** as the ground both stand on.
Between the peaks sits the *valley*: what the agent did — the vault's state,
the latest changes, the open issues, and a link to the decisions. Click an area to open its page; each page shows that cabinet's
sections as tiles; a tile opens the section's list; a list opens the page.

**Tiles.** Each tile carries its section ID (R1…R6, A1…A5, C1…C7), a count, a
**Maturity** bar (draft → review → accepted → deprecated) and, where open
issues point at pages of that section, a flag with their number.

**Colours mean place, not action.** Green is requirements (req42's colour,
problem space), blue is architecture (arc42's colour, solution space), red is
organisation and project. The sections diagram below predates this choice and
still draws requirements in blue and architecture in green. A
section shared by two areas shows two colours. The thin bar under the top
row tells you which area you are in.

**Nav and search.** The top row leads to content: Requirements, Architecture,
Domain Terms, Decisions and Issues. ⌘K (Ctrl K) jumps to search.

**Menu (≡).** *Configure* opens the visibility dialog; *Theme* switches
light/dark for this browser; *Who's here* lists connected clients; *Reload*
re-reads the wiki from disk; *Disconnect all* (facilitator only) ends the
session for everyone.

**Configure.** Untick an area or a section to hide it from the home page,
the area pages and the nav. Hidden pages stay reachable by URL and in search.
Only the **facilitator** — the first connected client, "Yoda" (or, once Yoda
has left, whoever inherited the role under their own name) — can save; the
dialog writes `_system/dashboard.yaml`, which you can also edit by hand. It is
the only file the dashboard ever writes; the wiki itself is read-only here.

## The LLM wiki {: #llm-wiki }

The wiki behind this dashboard is written by an AI agent and curated by
humans. It has three layers:

- **`raw/`** holds the sources: interview notes, transcripts, specs, tickets.
  Humans own them and the agent never edits them.
- **`wiki/`** holds the typed, interlinked pages the agent writes from those
  sources. Every page names its sources and carries a status.
- **The schema** (templates, anchors, the [metamodel](/metamodel)) tells the
  agent which kinds of pages exist and how they link.

The dashboard only reads `wiki/`. To change a page, change the source or ask
the agent, then reload.

## The Systems42 model in brief

{{DIAGRAM}}

**req42** (R1–R6) holds the requirements side: Vision & Goals, Functional
Requirements and Supporting Models are captured here; Resources, Team and
Roadmap are deliberately left to the organisation.

**arc42** (A1–A5) holds the architecture side: Solution Strategy, Building
Block, Deployment and Runtime views and Crosscutting Concepts. The content
types are a planned extension; the cabinet is shown so the shape is already
visible.

**Commons** (C1–C7) are the sections both sides depend on: Quality
Requirements, Constraints, Scope & Context, Stakeholders, Domain Terms,
Issues and Decisions. Architecture and business decisions share
one list there, filterable by kind; the diagram still draws architecture
decisions as A6.

## The metamodel

Which kinds of pages the wiki holds, which frontmatter fields link them, and
which views are only ever projected from them is declared in
`_system/metamodel/`, one page per type, relation, framework section,
projection and rule. **[Metamodel](/metamodel)** shows it: the types as a
network grouped by section, with the relations as arrows, and tables with
each construct's definition, its fields and a live example page from this wiki.
It is also where the granularity scale and its open question (use cases versus
epics) are shown.

## From requirements to architecture

Decision records and building blocks name the requirements they rest on in
`drivers:`. A building block page lists them under **Drivers**, together with
the decisions that shaped it and the blocks that use it; a goal, use case,
functional or quality requirement or constraint shows under **Addressed by**
which decisions and blocks answer it. **[Building Block View](/arc42/building-blocks)**
shows the levels; a block with parts shows its white box, drawn live from the
parts and their `uses:`.

The other architecture views work the same way. **[Deployment View](/arc42/deployment)**
draws where blocks run, from each node's `parent:`, `hosts:` and `connects:`.
**[Runtime View](/arc42/runtime)** lists the scenarios; each scenario page draws
its sequence diagram from `steps:` and warns when a step between two blocks has
no `uses:` edge. **[Crosscutting Concepts](/arc42/concepts)** groups the rules
that several blocks or nodes follow.

Every architecture page carries a `state`: **outdated** (historical, no longer
in use), **current** (in use today), **planned** (decided, not built yet) or
**target** (the intended end state). The building-block and deployment views
draw all of them in one picture: current plain, planned and target dashed,
outdated or deprecated grey, a dotted arrow from a replaced element to its
successor. Decision records that were overruled show *Replaced by* as well. A replaced page
links its successor under **Replaced by**; the successor shows **Replaces**.

## Spawned from Systems42

A project wiki is created from the Systems42 meta repository with `make new`
(or the `/new-project` skill). It receives the method — `AGENTS.md`,
templates, anchors, workflows, skills, this dashboard, the docs — and none of
the meta repository's content. **No decision records are taken over**:
decisions are content, so `wiki/decisions/` starts empty and the project's own
decisions start at DR-001. The method files state their rules themselves.
`make sync` later refreshes the method files and never touches the wiki.

For the full method see `docs/GETTING-STARTED.md` and `docs/req42/` in the
repository.
