# Goals of the Systems42 dashboard, second draft

Draft of 2026-11-10. Five goals, one per sentence of the vision (`02-vision.md`),
each in PAM format: purpose, advantage, metric. The 36 goals of `03-goals.md` are
merged into them. Their gaps are kept here in one line each, the detail stays there.

Every target is a proposal. No baseline has been measured.


## O1 Answers without asking a colleague

*Vision: "finds the answer in the Systems42 dashboard faster than by asking a colleague."*
*For: development teams, newcomers, workshop participants, domain experts.*

- **Purpose.** A reader with a question about the system gets the answer from the
  dashboard alone, whether they know the right word or not.
- **Advantage.** Development teams keep working instead of waiting for a reply.
  Product owners and architects are not interrupted with questions the wiki
  already answers. A newcomer in month six is productive without a guide.
- **Metric.** Share of 10 prepared questions that a reader who has never seen the
  wiki answers correctly within 60 seconds each. Proposed target: 8 of 10.

Merged from `03-goals.md`:

- **G01, G02 Search.** Works by ID, name and full text. Gaps: no tolerance for
  typing errors or word forms, tags and fields are not searched.
- **G03, G04 Browse and orient.** Works. Gap: two tiles carry another name than the
  page they open ("Domain Terms" and Glossary, "Risks & Assumptions" and Issues).
- **G11, G12 Domain terms.** Works. Gaps: Glossary is not in the top navigation, has
  no search box, and a definition cannot be read in place.
- **G13 Method terms.** Not served. `[[INVEST]]` or `[[MoSCoW]]` render without
  link or explanation.
- **G14 The dashboard's own words.** Help exists but contradicts itself and uses
  wording such as "Karpathy LLM-wiki".
- **G29 Point someone to one thing.** Every page has a stable address. Gap: filters
  and sort orders are not part of it.


## O2 Requirements with their reasons and their checks

*Vision: "They see what is required and why."*
*For: product owners, business analysts, testers, development teams.*

- **Purpose.** For every requirement the reader sees what is demanded, which goal
  it serves, how important it is and how it is checked.
- **Advantage.** Product owners decide scope with the reasons in front of them.
  Development teams build what was meant. Testers know what counts as passed,
  and today they are the least well-served group.
- **Metric.** Time a product owner or tester needs to list the requirements of the
  next release, each with its goal and its acceptance criteria. Proposed target:
  under 2 minutes.

Merged from `03-goals.md`:

- **G15 What the system has to do.** The hierarchy shows. Gap: no filter by
  priority, release or status.
- **G16, G17 Goals and stakeholders behind the requirements.** Served.
- **G18 Qualities and limits.** Lists exist. Gap: no columns for attribute and
  priority, so "all security requirements" has no direct answer.
- **G19 Where the system ends.** Served by the projected context diagram.
- **G22 What to test.** Not served. No page collects acceptance criteria or shows
  which requirements lack them.


## O3 Architecture and decisions traced to requirements

*Vision: "how the system is built to meet it, and what has been decided."*
*For: software architects, development teams, operations staff.*

- **Purpose.** From any requirement the reader reaches the building blocks and
  decisions that answer it, and from any block or decision the requirements
  behind it. They see which parts hold today.
- **Advantage.** Development teams know the limits and the reasons before they
  change something. Architects stop explaining the same decision again. Nobody
  builds on a decision that was replaced.
- **Metric.** Number of pages a reader opens to follow one chain from goal to
  requirement to decision to building block. Today one per step. Proposed
  target: 1.

Merged from `03-goals.md`:

- **G08, G09 Find a decision and its reasons.** Served. Gaps: Decisions is not in
  the top navigation, drivers show as bare IDs.
- **G10 Does the decision still hold.** Status and successor show. Gap: no filter
  by status, replaced decisions sit among valid ones.
- **G20 Architecture today and tomorrow.** All four views exist. Gap: the picture
  cannot be reduced to "today only".
- **G21 Follow a thread from goal to architecture.** Works one step at a time. Gap:
  no view shows a whole chain.


## O4 Source and status on every statement

*Vision: "They can tell where each answer came from and how firm it is."*
*For: requirements engineers, product owners, auditors and quality assurance.*

- **Purpose.** Wherever a statement appears, the reader sees its status and its
  source, and can restrict any view to what is agreed.
- **Advantage.** Nobody acts on a draft believing it is agreed. Product owners
  see what is still open. Requirements engineers spot unsourced claims.
  Auditors trace a requirement without interviewing anyone.
- **Metric.** Share of 10 statements for which a reader correctly names the status
  and the source. Proposed target: 10 of 10.

Merged from `03-goals.md`:

- **G05, G06 Open issues, overall and per page.** Served. Gaps: the tile's count
  is no link, and "Linked from" shows a resolved issue like an open one.
- **G07 Who answers an issue, by when.** Not served. Needs fields on the Issue type.
- **G23 Where a statement comes from.** Source chips work. Gap: the original
  document cannot be opened.
- **G24 How firm a statement is.** Status shows everywhere. Gap: no view of the
  agreed content only.
- **G25, G26 Current state and changes.** Gaps: "Data last refreshed" is the page
  load time, and the change list relies on file dates that a clone resets.


## O5 Readers who come back

*Vision: "The pages are a pleasure to read, so people come back."*
*For: everyone, first of all newcomers, workshop participants and people
presenting Systems42.*

- **Purpose.** Readers return to the dashboard on their own, because reading it
  is easier than any alternative.
- **Advantage.** A wiki that is read gets corrected. A wiki nobody opens goes
  stale, and the effort of recording it is lost.
- **Metric.** Share of the project team that opens the dashboard at least once a
  week without being asked. Proposed target: 80 percent, asked in the team, since
  the dashboard does not track readers.

Merged from `03-goals.md`:

- **G35 Enjoy looking at it.** A defined look exists. Gap: nothing checks
  "attractive", and two `linear-gradient` uses break the "no gradients" rule.
- **G36 Keyboard and screen reader.** Basics exist. Gaps: pages declare English for
  German content, hover-only information, no accessibility test.
- **G33 An empty wiki looks intended.** Served.


## Existing goals the vision does not carry

These six describe how the dashboard is run or shared, not why it exists.
Recommendation: record them as requirements or constraints below the goals,
not as goals.

| Existing goal | Recommendation |
|---|---|
| G27 Get the room onto the dashboard | Feature under O1 |
| G28 Keep the room on what matters | Feature. See `ISS-001` on who holds the keys |
| G30 Take results out | Open. Decide first whether export is wanted |
| G31 Start it with one command | Quality requirement |
| G32 Never put the wiki at risk | Constraint: the dashboard never writes to the wiki |
| G34 Understand how the wiki is built | Feature under O1, next to G13 |

If workshops are a reason the dashboard exists, the vision needs a sentence on
them and G27 and G28 become a sixth goal.


## What the comparison shows

- `03-goals.md` lists 36 tasks sorted by screen area, none with a metric. They read
  as an inventory of the current dashboard. The five goals above state outcomes
  and each has one test.
- Four of the five metrics are a timed or counted test with real readers. They
  need a prepared question set and a filled wiki, such as the iSAQB atrium wiki.
- The four gaps that can mislead a reader (G06, G24, G25, G26) all fall under O4.
  That goal has the most work open.
- Testers (G22) and method terms (G13) are the largest unserved needs. They fall
  under O2 and O1.
