# Code archaeology

Something exists and works, but no requirement says what it should do. The agent
reads the code, describes what it does today, and that description is captured.

The [Recover loop](../../_system/workflows/recover.md) (`recover` skill) does
this for a whole scope, top-down to a limited depth, and writes the report.

## When it fits

- A system was built before its requirements were written down.
- A feature grew in the code, and the wiki does not know it.
- You want to change something and first need to know what it does now.

## Steps

1. **Pick one feature,** not the whole system.
2. **Let the agent describe it from the code,** in the words of a user: what it
   shows, what it does, what it refuses. Name the release or commit it read.
3. **Put the description into `raw/`.**
4. **Grill it.** For each point, the human decides: is this wanted, or did it just
   happen? What is wanted becomes a requirement. What is not wanted is settled by
   that answer: it stays out of the wiki, or becomes a requirement to change the
   behaviour. Only a point the human cannot or does not want to decide yet becomes an
   Issue, after the closing round.
5. **Capture.** Mark what is built and what is only wanted, so nobody mistakes one for
   the other.

## What lands in `raw/`

A description of the feature as it is, with the release or commit it was read from,
split into "today" and, if any, "planned".

## Who decides, and where it is recorded

The human, in the grilling: the code says what is, not what should be. The grilling
record and the log name each decision.

## Pitfalls

- **Everything in the code becomes a requirement.** Some behaviour is an accident.
  Ask for each point whether it is wanted.
- **Implementation leaks into the requirement.** Write what the user sees, not how the
  code does it. A choice between real alternatives that is expensive to reverse may
  be a decision record; most of the rest is code.
- **The code moves while you capture.** Name the release you read and check it again
  before you write the pages.

## Example

The Systems42 dashboard's requirements were largely extracted from its code, one
feature at a time, for example the shared session in a workshop
([systems42-dashboard SRC-032](https://github.com/systems42-org/systems42-dashboard/blob/main/raw/sources/SRC-032-shared-session-in-a-workshop.md)).
The grilling decided which behaviours stay, and which ones, such as where the view
is stored, change.
