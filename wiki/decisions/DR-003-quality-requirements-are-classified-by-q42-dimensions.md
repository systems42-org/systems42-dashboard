---
id: DR-003
type: decision-record
title: Quality requirements are classified by Q42 dimensions
status: accepted
created: 2026-11-12
updated: 2026-11-12
sources: ["[[SRC-018-grilling-session-on-phone-and-tablet]]"]
related: ["[[QR-001-usable-on-phone-and-tablet]]", "[[STK-003-requirements-engineers]]", "[[STK-009-software-architects]]"]
tags: [decision-record]
aliases: []
kind: architecture
decided: 2026-11-12
decision-makers: [Gernot Starke]
consulted: [Claude]
informed: []
drivers: ["[[QR-001-usable-on-phone-and-tablet]]", "[[GOAL-004-requirements-with-reasons-and-checks]]"]
amends: []
superseded-by: []
---

# Quality requirements are classified by Q42 dimensions

> follows [[MADR]]

## Context and Problem Statement

Every quality requirement carries a classification, so readers can group and find them. Until now it was one ISO 25010 attribute (`attribute:`), such as usability or portability.

The first quality requirement, [[QR-001-usable-on-phone-and-tablet]], touches two qualities at once: it must be usable and it must adapt to the screen. ISO 25010 puts these in different branches of its hierarchy and allows only one.

How should quality requirements be classified?

## Decision Drivers

- A quality requirement often touches several qualities. The classification must not force a choice the requirement does not make.
- The wiki already writes its quality scenarios after [[Q42]] ([quality.arc42.org](https://quality.arc42.org)). The classification should fit the same model.
- Readers filter and group by the classification ([[GOAL-004-requirements-with-reasons-and-checks]]).

## Considered Options

1. **One ISO 25010 attribute.** Keep `attribute:` with its single value.
2. **Several ISO 25010 attributes.** Make `attribute:` a list.
3. **Q42 dimensions.** A list `dimensions:` with one or more of Q42's nine dimensions: reliable, flexible, maintainable, efficient, usable, safe, secure, suitable, operable.
4. **Both.** One ISO attribute and a list of Q42 dimensions.

## Decision Outcome

Chosen option: **3, Q42 dimensions**, because Q42 allows several dimensions on one requirement, while ISO 25010 forces a strict hierarchy with a single attribute. Q42's dimensions overlap by design, which matches how real quality requirements behave. The scenario format is Q42 already, so classification and scenario now come from one model.

### Consequences

- Good: a requirement names every quality it touches, and appears under each of them.
- Good: one model for classification and scenario, with Q42's examples per dimension as a source for measures.
- Bad: ISO 25010 names no longer appear in the classification. A reader who knows only ISO must map them.
- Bad: projects created from Systems42 before this change carry `attribute:` and must move to `dimensions:` when they sync the method. The dashboard no longer reads `attribute:`.

### Confirmation

- The metamodel lint checks that the template and the metamodel declare `dimensions:`.
- A dashboard test shows one badge per dimension on the quality requirements list.

## Pros and Cons of the Options

- **Option 1.** Good: a known standard, nothing to change. Bad: forces one attribute where a requirement touches several.
- **Option 2.** Good: keeps ISO names. Bad: works against ISO's own strict hierarchy, and still differs from the Q42 scenario model.
- **Option 3.** Good: several dimensions, one model with the scenario. Bad: ISO names disappear.
- **Option 4.** Good: both vocabularies. Bad: two classifications to keep consistent, and the ISO one still forces a single choice.

## More Information

The change touches `_templates/quality-requirement.md`, `_system/metamodel/types/type-quality-requirement.md`, the Q42 and req42 anchors, `AGENTS.md`, `docs/req42/README.md` and the dashboard's quality list. Recorded in `CHANGELOG.md`.
