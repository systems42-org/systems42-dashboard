# Workshop

Several people meet, in one room or one call, and decide together. Someone writes
the decisions down. Afterwards one person captures the minutes alone, with the agent.

## When it fits

- Many small points need a decision, and a back-and-forth in writing would take days.
- The people who decide can meet.
- The group needs to see the same thing at the same time, for example the wiki on
  everyone's own device.

## Steps

1. **Prepare.** Name the points to decide. The agent can list open Issues or gaps
   for the agenda.
2. **Meet and decide.** For each point, record the decision, who owns it, and its
   priority in the group's own words.
3. **Write the minutes into `raw/`,** as they were taken. Do not tidy them into
   requirements yet; that is the agent's job.
4. **Capture alone.** One person runs the capture. The agent grills the minutes
   against the wiki and asks its closing round.
5. **Bring back what the minutes do not answer.** The agent puts every open question
   to you in its closing round first. If you defer one to the group, it becomes an
   Issue and goes on the next agenda, or into an issue thread.

## What lands in `raw/`

The minutes: who was there, the date, each decision, its owner and its priority.
A table per topic works well.

## Who decides, and where it is recorded

The group, in the meeting. The minutes are the record. The person who captures
decides only what the minutes leave open and is small enough to settle alone, and
says so in the closing round; anything else goes back to the group.

## Pitfalls

- **Priorities in the minutes use another scale.** "High" and "low" are not
  [MoSCoW](../../_system/anchors/moscow.md). The agent asks how they map before it
  writes pages.
- **An idea is taken for a decision.** The minutes mention something that was only
  floated. The agent asks whether it was agreed; if not, it is recorded as an idea,
  not as an agreed requirement, wherever the human wants it kept.
- **A wish loses its owner.** Note who asked for what. Months later, "an explicit wish
  of the sponsor" carries weight that "someone said" does not.
- **The person who captures decides too much.** The closing round is for questions
  the writing threw up, not for reopening what the group settled.

## Example

The Systems42 team met on 2026-10-12 and recorded its decisions as a table of
topics, priorities and status
([meta SRC-007](https://github.com/systems42-org/meta/blob/main/raw/sources/SRC-007-team-meeting-2026-10-12.md)).
One person captured it alone the next day. The grilling had nine questions, all
answered, and mapped the minutes' scale to MoSCoW: "Hoch" became Should, "Mittel"
became Could, and every Must was set explicitly. A month later, the minutes were still the
place to check that hiding cross-references was rated "Hoch". That it was one
participant's explicit wish was not in them and had to come from memory, which is
why the pitfalls say to note who asked for what. For the meeting itself, the Systems42
dashboard offers a shared session: participants join on their own devices with a QR
code, and one person decides what the group sees.
