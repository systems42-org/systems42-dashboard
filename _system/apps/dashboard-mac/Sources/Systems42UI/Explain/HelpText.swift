/// The help text of the Systems42 Dashboard (Help > Systems42 Dashboard Help).
/// Copied from `_system/apps/dashboard/help.md`, the web dashboard's help page. Resources are reserved
/// for the diagram assets, so the text lives here as Swift source. It describes the web dashboard's
/// pages, header and footer: the native app offers the same things in its menus, which About and
/// the menu bar show. Changes: the sections on the browser UI, the start sentence, the diagram
/// placeholder, the heading attribute and the sentence on the diagram are left out, the description of the
/// web view of the metamodel and "then reload" are changed, and links into the web dashboard are plain text.
/// Update this copy when `help.md` changes.
public enum HelpText {
    public static let markdown = #"""
    # Help

    This text comes from the help of the web dashboard. In the Mac app, the same things are in the menus: Help > Metamodel, The Method and Guided Tour.

    ## The LLM wiki

    The wiki behind this dashboard is written by an AI agent and curated by
    humans. It has three layers:

    - **`raw/`** holds the sources: interview notes, transcripts, specs, tickets.
      Humans own them and the agent never edits them.
    - **`wiki/`** holds the typed, interlinked pages the agent writes from those
      sources. Every page names its sources and carries a status.
    - **The schema** (templates, anchors, the metamodel) tells the
      agent which kinds of pages exist and how they link.

    The dashboard only reads `wiki/`. To change a page, change the source or ask
    the agent.

    ## The Systems42 model in brief

    **req42** (R1–R6) holds the requirements side: Vision & Goals, Functional
    Requirements and Supporting Models are captured here; Resources, Team and
    Roadmap are deliberately left to the organisation.

    **arc42** (A1–A5) holds the architecture side: Solution Strategy, Building
    Block, Deployment and Runtime views and Crosscutting Concepts.

    **Commons** (C1–C7) are the sections both sides depend on: Quality
    Requirements, Constraints, Scope & Context, Stakeholders, Domain Terms,
    Issues and Decisions. Architecture and business decisions share
    one list there, filterable by kind.

    ## The metamodel

    Which kinds of pages the wiki holds, which frontmatter fields link them, and
    which views are only ever projected from them is declared in
    `_system/metamodel/`, one page per type, relation, framework section,
    projection and rule. **Help > Metamodel** shows it: each
    construct's definition and fields and, for a type, an example page from this wiki.
    It also lists the requirement notations: every functional requirement names
    its `notation:` (Agile, use case, EARS, prose or a project's own) and one of
    that notation's `level:` values, and each notation file defines its levels,
    extra fields and page sections.

    ## From requirements to architecture

    Decision records and building blocks name the requirements they rest on in
    `drivers:`. A building block page lists them under **Drivers**, together with
    the decisions that shaped it and the blocks that use it; a goal, use case,
    functional or quality requirement or constraint shows under **Addressed by**
    which decisions and architecture pages answer it. **Building Block View**
    shows the levels; a block with parts shows its white box, drawn live from the
    parts and their `uses:`.

    The other architecture views work the same way. **Solution Strategy**
    lists the strategy pages, each with its drivers and the decisions it summarises.
    **Deployment View**
    draws where blocks run, from each node's `parent:`, `hosts:` and `connects:`.
    **Runtime View** lists the scenarios; each scenario page draws
    its sequence diagram from `steps:` and warns when a step between two blocks has
    no `uses:` edge. A scenario names the functional requirement or activity model it
    carries out in `realizes:`; that page lists it under **Realized by**. **Crosscutting Concepts** groups the rules
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
    """#
}
