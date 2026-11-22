# Working patterns

Systems42 has one way into the wiki: a source, grilled, then captured. Most sources
are a file in `raw/`; a conversation with the agent is recorded without one.
How that source comes about differs from team to team and from case to case.
This folder describes the ways we have seen work.

**These are descriptions, not rules.** Pick the one that fits, mix them, or find
your own. The agent's procedures are in `_system/workflows/`; nothing here changes
them.

## The patterns

| Pattern | When it fits | What lands in `raw/` |
|---|---|---|
| [Issue discussion](issue-discussion.md) | A change that several people discuss over days, in GitHub or another tracker | A summary of the issue and its decisions |
| [Workshop](workshop.md) | Several people decide together, in one room or one call | The minutes, with the decisions |
| [Interview or transcript](interview-or-transcript.md) | One stakeholder, or a recorded meeting | The transcript or the notes |
| [Dictation](dictation.md) | One person knows what they want and says it | The dictated text as it was said, or the voice recording |
| [Code archaeology](code-archaeology.md) | Something exists and works, but no requirement says so | A description extracted from the code |
| [Conversation](conversation.md) | The answers come up while you talk to the agent | Nothing: the record notes the chat |

## What they share

- **The source is written before the pages.** Whatever the route, a decision becomes
  a file in `raw/` (or, for a conversation, a source record that names the chat)
  before it becomes a wiki page. Provenance is what makes the wiki trustworthy.
- **Grilling comes before writing, and a closing round after it.** Before it writes
  any page, the agent stress-tests the source against the wiki. Once the pages are
  drafted, it puts the questions the writing threw up to the human in a numbered
  closing round, each with its recommended answer: every question that can be asked
  now in one message, and questions that depend on an answer in the next round. Only
  what the human declines, defers or cannot answer becomes an Issue.
- **The human decides.** The agent summarises, files and flags. A choice that
  nobody made stays an open question.
- **Delivery follows the commit policy** in `AGENTS.md`: draft pages go to `main`,
  and promoting a page to `accepted` goes through a pull request.

## Format of a pattern

Each pattern has the same sections: when it fits, the steps, what lands in `raw/`,
who decides and where that is recorded, pitfalls, and an example from a Systems42
project (the meta repository or the dashboard).

## Candidates

Patterns we have seen once, not yet written up:

- **Observation.** Someone notices a defect or an odd behaviour and writes it down,
  for example "the dashboard stopped in Firefox while a page was open"
  ([meta SRC-011](https://github.com/systems42-org/meta/blob/main/raw/sources/SRC-011-dashboard-firefox-shutdown.md)).
