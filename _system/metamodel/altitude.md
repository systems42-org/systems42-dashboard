---
type: metamodel
construct: altitude-scale
name: granularity
aliases: [altitude, granularity]
rungs: [summary, user-goal, subfunction]
assignments:
  - {type: functional-requirement, stereotype: epic, rung: summary, status: proposed}
  - {type: functional-requirement, stereotype: feature, rung: user-goal, status: proposed}
  - {type: functional-requirement, stereotype: story, rung: subfunction, status: proposed}
  - {type: use-case, field: level, rung: "value of level", status: open, note: "see Open below"}
  - {type: activity-model, rung: null, status: open}
---

# Altitude: comparable granularity across types

Three rungs, Cockburn's names, coarse to fine: **summary** (a theme, several
sessions), **user-goal** (one actor, one sitting), **subfunction** (a step inside
a goal). The FR stereotypes map onto them one-to-one — *proposed*, not yet agreed.

## Open: use cases versus epics
The human's position (2026-10-16): use cases and epics **may be used in parallel**.
There may be use cases without any epic, and epics that have only features and
stories. Which rung a use case sits on is therefore not fixed by its type; the
candidate is its own `level:` field, which would make a `user-goal` use case
comparable to a feature and its main-flow steps comparable to stories. An
alternative reading puts a use case beside an epic and its steps beside features.
Until this is settled, **no rule compares altitude across types**, and naming
convention A (use cases named like stories, verb + object) stands as it is.

One fact is fixed (2026-10-19, DR-011):
a feature or story may name a use case as its parent ([[rel-parent]]), so a use
case is coarser than the features and stories below it. Where it stands
against an *epic* is still open; an epic never sits under a use case.
