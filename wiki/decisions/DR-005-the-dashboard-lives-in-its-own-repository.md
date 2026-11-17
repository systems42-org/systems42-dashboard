---
id: DR-005
type: decision-record
title: The dashboard lives in its own repository, with its requirements and its code
status: review
created: 2026-11-17
updated: 2026-11-17
sources: ["[[SRC-027-dashboard-distribution-and-metamodel-contract]]", "[[SRC-028-grilling-session-on-dashboard-distribution]]"]
related: ["[[DR-004-releases-are-container-images-pinned-per-wiki]]", "[[FR-029-the-dashboard-as-a-product]]", "[[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]]", "[[ISS-005-the-method-lint-imports-dashboard-code]]", "[[STK-012-maintainers]]"]
tags: [decision-record]
aliases: []
kind: architecture
decided: 2026-11-17
decision-makers: [Gernot Starke]
consulted: [Claude]
informed: []
drivers: ["[[GOAL-008-one-way-into-every-systems42-wiki]]", "[[FR-029-the-dashboard-as-a-product]]"]
amends: []
superseded-by: []
---

# The dashboard lives in its own repository, with its requirements and its code

> follows [[MADR]]

## Context and Problem Statement

The dashboard code existed in three repositories and the copies had drifted: `systems42-org/meta`, systems42-dashboard and isaqb-atrium. Its requirements were split between meta's wiki and this one. [[DR-004-releases-are-container-images-pinned-per-wiki]] says how a release reaches a wiki, and names this repository as the code's home only in passing.

Where do the dashboard's code and its requirements live, relative to the Systems42 method in meta?

## Decision Drivers

- Systems42 is meant to generate code from requirements and architecture decisions, so a system's requirements and its code belong together.
- Method and dashboard are coupled: a change of the metamodel can need a dashboard change.

## Considered Options

1. **Own repository.** systems42-dashboard holds the dashboard's requirements and its code. meta holds only the method.
2. **Everything in meta.** Method, dashboard code and the dashboard's requirements in one repository.
3. **Code in meta, requirements here.**

## Decision Outcome

Chosen option: **1, own repository**, because requirements and code stay together, and the dashboard is then a system built with Systems42 like any other. [[DR-004-releases-are-container-images-pinned-per-wiki]] stands unchanged.

### Consequences

- Good: one home for the code and one wiki for its requirements.
- Good: the dependency has to run one way ([[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]]).
- Bad: a change that spans method and dashboard needs a pull request in each repository and a version step ([[FR-043-the-dashboard-checks-the-metamodel-version]]).
- Bad: meta's dashboard requirements and decisions (its FR-010, FR-011, FR-034, DR-022 to DR-025, DR-032, DR-033) have to move here under new IDs.
- Bad: meta must drop its copy of the code and stop depending on it ([[ISS-005-the-method-lint-imports-dashboard-code]]).

## Pros and Cons of the Options

- **Option 1.** Good: as above. Bad: two repositories and two release lines for a small team.
- **Option 2.** Good: one pull request for a change that spans both, and one CI run against the current metamodel. Bad: 41 FRs enter a wiki where the same IDs already mean something else, or one repository has to hold two wikis.
- **Option 3.** Good: one version for method and tool. Bad: separates the dashboard's requirements from its code.

## More Information

Follow-ups:
- Move meta's dashboard requirements and decisions into this wiki.
- Reconsider when the metamodel is stable or the dashboard gets maintainers of its own: the cost of option 1 falls with both.
