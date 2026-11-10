# Goals of the Systems42 dashboard

Draft of 2026-11-09. Based on the dashboard's code and documentation (`isaqb-atrium`,
`_system/apps/dashboard`, commit 2987898). Sorting of the issues table comes from
PR #20, which is not merged yet.

A goal says what a person wants to get done. It does not say how a screen does it.
Each goal states who it is for and which words of the vision it serves: visible,
navigable, efficient, attractive (see `02-vision.md`).

"Today" describes what exists. "Gap" describes what is missing or contradictory. A
gap is a finding, not yet a demand: some may turn out not to matter.

No goal has a number yet. I did not invent any, because targets such as "in three
clicks" should come from you or from observing real readers.


## Finding content

### G01 Get to a page whose ID or name I know

*For everyone. Vision: navigable, efficient.*

- Today: ⌘K or Ctrl K on any page opens a search box with results as you type. It
  covers IDs, titles, other names and page text, and works from the keyboard alone.
- Gap: a typing error finds nothing. Matching is on exact character sequences.

### G02 Find everything on a topic when I do not know the right word

*For everyone. Vision: navigable, efficient.*

- Today: `/search` searches the full text and narrows the results by page type.
- Gap: every word typed must appear. There is no handling of word forms, so a search
  for "Trainerinnen" does not find "Trainer".
- Gap: it searches only wiki pages, and within them only ID, title, other names and
  body text. Tags and fields such as a quality requirement's `attribute` are not
  searched. Neither are source records, Help, the metamodel or the method references.

### G03 Look around without having a search term

*For newcomers, workshop participants, sponsors. Vision: visible, navigable.*

- Today: home page, then area, then section tile, then list, then page.
- Gap: the same thing goes by two names. The "Domain Terms" tile opens "Glossary", and
  the "Risks & Assumptions" tile opens "Issues". A newcomer cannot tell that these are
  the same.

### G04 Know where I am and how to get back

*For everyone. Vision: navigable.*

- Today: the same top bar everywhere, breadcrumbs, the current section marked, and a
  coloured bar for the area.


## Issues

### G05 See what is open and how serious it is

*For product owners, requirements engineers, facilitators, sponsors. Vision: visible,
efficient.*

- Today: the home page shows the count and the open issues, most severe first.
  `/issues` filters by All, Open and Closed and sorts by every column.
- Gap: `/issues` itself starts with all issues in ID order, so it does not open on the
  most serious ones. A link from the home page does preselect Open.

### G06 See which open issues concern what I am looking at

*For requirements engineers, product owners, development teams. Vision: navigable.*

- Today: a tile shows how many open issues point at its section. A page lists issues
  that link to it under "Linked from".
- Gap: the tile's count is not a link, and the issue list cannot be filtered by section
  or by affected page.
- Gap: "Linked from" shows ID and title but no status, so a resolved issue looks the
  same as an open one.

### G07 See who has to answer an issue, and by when

*For product owners, facilitators. Vision: visible.*

- Gap: not served. Issues record who raised them, but they have no field for who should
  answer or for a date. This needs a change to the content type as well, not only the
  dashboard.


## Decisions

### G08 Find a specific decision

*For architects, development teams, product owners. Vision: navigable, efficient.*

- Today: `/decisions` has its own search box (title, ID, former ADR number, full text),
  a filter by kind, and sortable columns.
- Gap: Decisions is not in the top navigation. It is reached through Commons, the home
  page or the footer.
- Gap: the filter by kind cannot be shared as a link (see G29).

### G09 Understand why it was decided that way

*For architects, development teams, newcomers, auditors. Vision: navigable.*

- Today: clicking a row shows the full text below the table, including the alternatives
  considered. The Drivers column links to the requirements behind the decision.
- Gap: Drivers appear as bare IDs, with the title only on mouse hover. A workshop
  participant on a phone sees only codes.

### G10 Know whether a decision still holds

*For architects, development teams, auditors. Vision: visible.*

- Today: each decision shows its status and date, and a replaced one links to its
  successor under "Replaced by".
- Gap: the list has no filter by status, so decisions no longer in force sit among the
  valid ones unless you sort. The successor appears only on the decision's own page.


## Terms

### G11 Look up what a domain term means

*For everyone, especially domain experts, newcomers, workshop participants. Vision:
visible, efficient.*

- Today: `/glossary` shows one definition per term, other names, status and an
  "Assumption" badge for unconfirmed definitions.
- Gap: Glossary is not in the top navigation either. It is one of the most frequent
  questions in a workshop, yet it takes a detour through Commons or the footer.
- Gap: unlike Decisions, the page has no search box of its own.
- Gap: in running text a term links to its definition only where the author wrote a
  link, and the definition does not appear in place. Reading it means leaving the page.

### G12 See how terms relate to each other

*For business analysts, domain experts, requirements engineers. Vision: visible,
navigable.*

- Today: the term network at `/graph/glossary`, and a local network on a term's page.

### G13 Look up method terms such as MoSCoW, INVEST or MADR

*For workshop participants, domain experts, newcomers, sponsors. Vision: visible,
navigable.*

- Gap: not served. A reference such as `[[INVEST]]` on a wiki page appears as styled
  text with no link. The explanations exist in `_system/anchors/`, but the dashboard
  does not read that folder. `/metamodel` shows these names as labels, also with no
  explanation. A reader meets "Must", "PAM" or "Q42" and has to ask someone.

### G14 Understand the dashboard's own vocabulary

*For workshop participants, newcomers. Vision: navigable, attractive.*

- Today: `/help` explains tiles, section IDs, maturity bars, colours and the menu.
- Gap: explanations sit on a separate page, not where the word appears.
- Gap: Help contradicts itself. It calls the arc42 content types "a planned extension",
  then links to the finished views further down. It also admits that its diagram uses
  the old colours and an A6 section that the dashboard no longer has.
- Gap: some wording means nothing to most readers. The footer says "Karpathy LLM-wiki",
  and Help describes the middle of the home page as "what the agent did".


## Requirements and architecture

### G15 See what the system has to do, and in what order

*For product owners, development teams, testers. Vision: visible, navigable.*

- Today: the hierarchy of epics, features and stories, plus use cases, with priority and
  release shown as labels.
- Gap: no filter by priority, release or status. "What is in the next release?" means
  reading the whole page.

### G16 See which goals are backed by requirements

*For product owners, business analysts, sponsors. Vision: visible.*

- Today: `/goals` shows the vision, the objectives with their counts of covering epics
  and use cases, and a goal tree.

### G17 See who is involved and what they want

*For product owners, UX designers, newcomers, facilitators. Vision: visible.*

- Today: `/stakeholders` lists each with a short profile, relations, influence and
  interest, all sortable.
- Gap: influence and interest are visible to everyone in the room (see
  `01-stakeholders.md`, "People described on stakeholder pages").

### G18 See which qualities are demanded and which limits apply

*For architects, development teams, testers, operations staff. Vision: visible,
efficient.*

- Today: separate lists for quality requirements and constraints.
- Gap: the quality list has no columns for attribute and priority. "Show me all security
  requirements" has no direct answer, and search helps only if the page text uses that
  word.

### G19 See where the system ends and what it talks to

*For architects, owners of neighbouring systems, sponsors, newcomers. Vision: visible.*

- Today: `/req42/scope` draws the context diagram from the recorded interfaces and
  stakeholders and lists the data flows. Nobody has to maintain the drawing by hand.

### G20 See the architecture, and tell today from tomorrow

*For architects, development teams, operations staff. Vision: visible.*

- Today: views for building blocks, deployment, runtime and concepts. Current, planned,
  target and outdated parts are drawn differently within one picture.
- Gap: all states always appear together, and a crowded picture cannot be reduced to
  "today only".
- Gap: the dashboard's README still lists these views as planned and "not captured yet".
  It also describes people in the context diagram as a 👤 symbol, while the code draws a
  box labelled "Person".

### G21 Follow a thread from goal to architecture and back

*For architects, requirements engineers, auditors. Vision: navigable.*

- Today: each page shows Links to, Linked from, Drivers, Addressed by and Realized by.
  The goal map shows the step from goal to epic.
- Gap: this works one step at a time. No view shows a whole chain on one page.

### G22 Find out what I have to test

*For testers, development teams. Vision: visible, efficient.*

- Today: stories carry acceptance criteria and quality scenarios carry a measure, in
  their own page text.
- Gap: not served as a task. No page collects acceptance criteria, shows which
  requirements lack them, or lists the measures across scenarios.


## Trusting what I see

### G23 See where a statement comes from

*For requirements engineers, auditors, domain experts. Vision: visible, navigable.*

- Today: every page shows its sources as chips, and an amber "unsourced" chip when it
  has none. `/source/...` shows the source record and the pages it fed.
- Gap: the trail ends at the record. The original document cannot be opened from the
  dashboard, because it does not read `raw/` beyond `raw/sources/`.

### G24 See how firm a statement is

*For everyone. Vision: visible.*

- Today: status on every page, maturity bars on tiles and lists, "Assumption" badges.
- Gap: there is no way to see only what is agreed. Search filters by type, not by
  status, and the lists can sort by status but not filter by it.

### G25 Be sure I am looking at the current state

*For everyone. Vision: visible.*

- Today: pages are read from disk on each request, and Reload forces a fresh read.
- Gap: the footer's "Data last refreshed" is the moment the page loaded. A wiki untouched
  for three months still reads as refreshed just now. It says nothing about the age of
  the content.

### G26 See what has changed

*For requirements engineers, product owners, testers, returning readers. Vision: visible,
efficient.*

- Today: the home page lists the latest changes.
- Gap: the list relies on file dates. A fresh clone resets all of them, so everything
  looks changed at once, and a pull dates each change to the pull, not to the edit.
- Gap: there is no "since my last visit", and no way to see what changed on a page.


## Working together

### G27 Get everyone in the room onto the dashboard

*For facilitators, workshop participants. Vision: visible, efficient.*

- Today: a QR code and a plain address on the home page, a full-size version at `/join`,
  no account, a live count of connected people.
- Gap: everyone must be on the same network and able to reach each other. Guest Wi-Fi
  often prevents that, and the fallback is setting `DASH_PUBLIC_URL` by hand.

### G28 Keep the room on what matters

*For facilitators. Vision: visible, attractive.*

- Today: the facilitator can hide areas and sections, and can end the session for everyone.
- Gap: the facilitator is simply whoever connects first, with nothing to prove it. If a
  participant's phone gets there first, they hold the role.
- Gap: hiding only tidies the view. Hidden pages stay reachable by address and in search,
  and Configure should not be mistaken for a way to keep something confidential.

### G29 Point someone to one specific thing

*For everyone. Vision: navigable, efficient.*

- Today: every page has its own address built on a stable ID, and `/issues?filter=open`
  can be linked.
- Gap: the kind filter on Decisions, column sort orders and the row selected in a list are
  not part of the address.
- Gap: a link works only while the dashboard is running and on the same network. A link
  starting with `localhost` works for nobody else.

### G30 Take results out of the dashboard

*For sponsors, auditors, facilitators after a workshop. Vision: visible.*

- Gap: not served. There is no print layout and no export. Whether this is wanted at all
  is an open decision.


## Running it, and how it looks

### G31 Start it without installing or learning much

*For people who run it, facilitators. Vision: efficient.*

- Today: one command (`./dashboard.sh` or `make dev`) starts it and opens the browser. It
  works offline with nothing fetched from the internet. `local` is the fallback when
  Docker will not start.
- Gap: it needs a copy of the repository plus Docker or Python. A reader without those
  depends on someone else to run it.

### G32 Never put the wiki at risk, and leave nothing behind

*For requirements engineers, people who run it. Vision: efficient.*

- Today: Docker mounts the wiki read-only, and one settings file is the only thing the
  dashboard writes. It stops by itself after the last tab closes, and `make clean` removes
  what can be rebuilt without touching content.
- Gap: in `local` mode there is no read-only mount. There the promise rests on the code
  alone.

### G33 A new, empty wiki looks intended, not broken

*For people who set up a new wiki. Vision: attractive.*

- Today: empty sections name the next step instead of showing a placeholder. A test checks
  that every page renders on an empty wiki.

### G34 Understand how the wiki is built

*For requirements engineers, maintainers, people learning Systems42. Vision: visible.*

- Today: `/metamodel` shows the page types as a network with their relations, plus tables
  with a live example from the wiki.

### G35 Enjoy looking at it

*For everyone, especially people presenting Systems42. Vision: attractive.*

- Today: a defined look. Flat panels, one border radius, its own fonts, light and dark
  themes, colours that mean a place (green for requirements, blue for architecture).
- Gap: nothing checks "attractive". It needs a judge, for example people who have never
  seen it, shown it for the first time.
- Gap: the written rule "no gradients" is not fully kept. `style.css:1204-1205` uses
  `linear-gradient` twice, and a design test fails because of it. Both uses repeat one
  colour, so they look flat: either the code or the test needs to change.

### G36 Use it by keyboard and with a screen reader

*For people who need it. Vision: navigable.*

- Today: labels for assistive technology, keyboard use in search and in table rows, and
  layouts that adapt to small screens.
- Gap: every page declares itself English, while the iSAQB atrium wiki's content is German,
  so a screen reader pronounces it wrongly.
- Gap: information given only on mouse hover does not reach touch-screen or keyboard users.
- Gap: no test script is dedicated to accessibility.


## Summary of the gaps

**Not served at all:** G07 who answers an issue, G13 method terms, G22 what to test, G30
taking results out.

**Served, but with a detour for a frequent need:** G08 and G11, because Decisions and
Glossary are missing from the top navigation although finding them is among the first
goals named for this dashboard.

**Could mislead a reader:** G06 resolved issues look open, G25 the "refreshed" time, G26
file dates, G28 hiding is not confidentiality.

**Documentation out of date:** G14 Help, G20 README.
