# Stakeholders of the Systems42 dashboard



### Product owners

- Want: to see what is agreed, what is still open, how it is defined or explained.

### Business analysts

- Want: to check that goals, processes and terms match how the business works.
- Note: in many organisations this is the same person as the requirements
  engineer. Kept separate here because the interest differs: the business itself, versus the state of the requirements.

### Requirements engineers

- Want: to review what has been recorded and to spot gaps, contradictions and
  claims without a source.
- Note: they cannot fix anything they find here. The dashboard never writes to
  the wiki, so every correction happens elsewhere.


### Development teams

- Want: to know what to build, within which limits, and why it was decided that
  way. Explanations of terms, functions, features, acceptance-criteria, quality requirements, or others.
- Note: they tend to read on their own, on any working day. 
- 
### Testers

- Want: to know what has to be checked and what counts as passed.
- Note: this is the least well-served group on the list. No page currently collects   acceptance criteria across requirements.

### AI agents

- Want: nothing from the dashboard as built. They read and write the files in
  `wiki/` directly.
- Note: they matter indirectly, because they write most of what the dashboard
  shows, so the file format is the contract between them and it. Suggest listing
  them as a source of content, not as users. See open question 2.


**Workshop facilitators.**  The dashboard has a facilitator
role: only the facilitator can save the visibility settings and end the session.
`/join` shows the QR code full-size for projecting. The top navigation is
described as "the five sections a workshop keeps returning to".

**Workshop participants.** People who scan the QR code and read on their own
phone or laptop, with no account and no installation. Many will know neither the
method nor the vocabulary, and each gets a nickname on the "Who's here?" page.
They get the _metamodel_ and other terms explained.

**Software architects.** A whole area of the dashboard is theirs: building blocks, deployment, runtime scenarios, crosscutting concepts, decisions with their drivers, and the marking of current, planned, target and outdated parts.

**People who run the dashboard.** Someone has to start it, stop it and clean up
after it (`dashboard.sh`, `make dev`, `make clean`), sometimes on a workshop
laptop where Docker will not start. This is sometimes the facilitator.


**People who set up a new project wiki.** `make new` gives them an empty wiki, so they see the empty states first. They also set the name, tagline and About page.

**Maintainers of the dashboard and the systems42 method.** `make sync` carries each change into every project wiki. The tests that hold templates, metamodel and dashboard together exist for them.

**People learning or presenting Systems42.** Trainers, consultants and speakers.
`/help` and `/metamodel` explain the method, and the dashboard is what they put on the screen to show it. This group is the strongest reason for "visually attractive".


**Domain experts.** They are asked whether a term or a process is right. They read and review the glossary and activity models, and they are the people who can remove an "Assumption" badge from a definition. They do not know the systems42 method and should not have to.

**Newcomers to a project.** Someone joining in month six needs the vision, the
glossary and the main decisions, in that order. Nothing leads them through.

**Sponsors and management.** They want the state of things and the main risks in
a few minutes. The home page comes close, but there is nothing they can receive
or keep: no print layout and no export.

**UX designers.** They need stakeholder profiles, use cases and activity models.

**Operations and infrastructure staff.** They need the deployment view, external
interfaces and constraints.

**Owners of neighbouring systems.** They need to see what the system expects from theirs: the context diagram and the data flows of an external interface.

**Auditors and quality assurance.** They ask where a requirement came from, who
decided what, and what replaced what. The source chips, source records and "Replaced by" links answer these questions, though the feature was not built for them.


**Data protection and security officers.** The dashboard has no login. It listens on all network interfaces, so anyone on the same network who knows the address can read everything, and a QR code is on the home page. 

That is reasonable for a trusted room, and it may not be for confidential requirements on hotel or customer Wi-Fi.



1. **One room, or everyday work?** As built, the dashboard runs on one person's
   machine and stops itself a few seconds after the last browser tab closes. 
That suits workshops. 

It does not suit development teams, testers, sponsors or
   auditors, who read at different times and from different places, because nothing is running when they want to look.
