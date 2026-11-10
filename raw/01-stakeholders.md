# Stakeholders of the Systems42 dashboard

Draft of 2026-11-09. Based on the initial list of seven groups and on the
dashboard's code and documentation (`isaqb-atrium`, `_system/apps/dashboard`,
commit 2987898).

A stakeholder here is anyone who reads the dashboard, runs it, feeds it,
maintains it, or is affected by what it shows.

"Uses today" names only what exists in the code. Where a group has no such
evidence, the entry says so and its reasoning is an assumption to check.


## From the initial list

### Product owners

- Want: to see what is agreed, what is still open, and what comes first.
- Use today: Vision & Goals, the functional requirements with priority and
  release, maturity bars, open issues.
- Note: the dashboard only shows status. Promoting a page to `accepted` happens
  outside it.

### Business analysts

- Want: to check that goals, processes and terms match how the business works.
- Use today: goals, activity models, data models, glossary.
- Note: in many organisations this is the same person as the requirements
  engineer. Kept separate here because the interest differs: the business itself,
  versus the state of the requirements.

### Requirements engineers

- Want: to review what has been recorded and to spot gaps, contradictions and
  claims without a source.
- Use today: open issues, "unsourced" chips, the Links to / Linked from panels,
  latest changes, Reload.
- Note: they cannot fix anything they find here. The dashboard never writes to
  the wiki, so every correction happens elsewhere.

### Product teams

- Want: one shared view of the product during meetings.
- Use today: the home page and the area pages on a shared screen.
- Note: a product team normally consists of the product owner, analysts,
  developers and testers, who are all listed separately. This entry only earns
  its place as "the team as a group, looking at one screen". Otherwise drop it.

### Development teams

- Want: to know what to build, within which limits, and why it was decided that
  way.
- Use today: functional requirements, use cases, constraints, decisions,
  glossary, building blocks.
- Note: they tend to read on their own, on any working day. See open question 1.

### Testers

- Want: to know what has to be checked and what counts as passed.
- Use today: requirement pages one at a time, quality scenarios with their
  measure.
- Note: this is the least well-served group on the list. No page collects
  acceptance criteria across requirements.

### AI agents

- Want: nothing from the dashboard as built. They read and write the files in
  `wiki/` directly.
- Use today: nothing. The only machine-readable address, `/search.json`, exists
  for the search box.
- Note: they matter indirectly, because they write most of what the dashboard
  shows, so the file format is the contract between them and it. Suggest listing
  them as a source of content, not as users. See open question 2.


## Missing from the initial list

### Already built into the dashboard

These groups have features made for them, so the code proves they count.

**Workshop facilitators.** The clearest omission. The dashboard has a facilitator
role: only the facilitator can save the visibility settings and end the session.
`/join` shows the QR code full-size for projecting. The top navigation is
described as "the five sections a workshop keeps returning to".

**Workshop participants.** People who scan the QR code and read on their own
phone or laptop, with no account and no installation. Many will know neither the
method nor the vocabulary, and each gets a nickname on the "Who's here?" page.

**Software architects.** A whole area of the dashboard is theirs: building blocks,
deployment, runtime scenarios, crosscutting concepts, decisions with their
drivers, and the marking of current, planned, target and outdated parts.

**People who run the dashboard.** Someone has to start it, stop it and clean up
after it (`dashboard.sh`, `make dev`, `make clean`), sometimes on a workshop
laptop where Docker will not start. This is often the facilitator, but the need
is different.

**People who set up a new project wiki.** `make new` gives them an empty wiki, so
they see the empty states first. They also set the name, tagline and About page.

**Maintainers of the dashboard and the method.** `make sync` carries each change
into every project wiki. The tests that hold templates, metamodel and dashboard
together exist for them.

**People learning or presenting Systems42.** Trainers, consultants and speakers.
`/help` and `/metamodel` explain the method, and the dashboard is what they put on
the screen to show it. This group is the strongest reason for "visually attractive".

### Served by existing pages, but not named anywhere

No feature is aimed at these groups, so whether they count is an assumption.

**Domain experts.** They are asked whether a term or a process is right. They read
the glossary and activity models, and they are the people who can remove an
"Assumption" badge from a definition. They do not know the method and should not
have to.

**Newcomers to a project.** Someone joining in month six needs the vision, the
glossary and the main decisions, in that order. Nothing leads them through.

**Sponsors and management.** They want the state of things and the main risks in
a few minutes. The home page comes close, but there is nothing they can receive
or keep: no print layout and no export.

**UX designers.** They need stakeholder profiles, use cases and activity models.

**Operations and infrastructure staff.** They need the deployment view, external
interfaces and constraints.

**Owners of neighbouring systems.** They need to see what the system expects from
theirs: the context diagram and the data flows of an external interface.

**Auditors and quality assurance.** They ask where a requirement came from, who
decided what, and what replaced what. The source chips, source records and "Replaced
by" links answer these questions, though the feature was not built for them.

### Affected without using it

**People described on stakeholder pages.** A stakeholder page can name a person or
a group and rate their influence and interest. Those ratings are readable by
everyone on the network and can appear on a projector in front of the people
rated. Decide whether that is acceptable before it happens in a workshop.

**Data protection and security officers.** The dashboard has no login. It listens
on all network interfaces, so anyone on the same network who knows the address can
read everything, and a QR code is on the home page. That is reasonable for a
trusted room, and it may not be for confidential requirements on hotel or customer
Wi-Fi.


## Deliberately not listed

- **End users of the system being specified.** The requirements describe them, but
  they do not read the requirements.
- **People who need keyboard or screen-reader access.** Not a role. They exist in
  every group above, so this belongs in the quality requirements.
- **Readers of another language.** Also not a role. The interface is English, while
  the iSAQB atrium wiki holds German content, so this is a quality question too.


## Open questions

1. **One room, or everyday work?** As built, the dashboard runs on one person's
   machine and stops itself a few seconds after the last browser tab closes. That
   suits workshops. It does not suit development teams, testers, sponsors or
   auditors, who read at different times and from different places, because nothing
   is running when they want to look. This is the largest mismatch between the list
   above and the implementation. The answer decides whether several of these groups
   are real stakeholders or wishful thinking.
2. **Do AI agents stay on the list?** Suggestion: yes, as a source of content, with
   no reading needs of their own.
3. **Product teams:** keep them as "the group at one screen", or drop them?
4. **Business analysts and requirements engineers:** one group or two?
5. **Who comes first?** A dashboard cannot optimise for everyone. Suggestion for the
   primary group: requirements engineers, facilitators, product owners and
   development teams. Please decide.
