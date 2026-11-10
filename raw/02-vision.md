# Long-term vision of the Systems42 dashboard

Draft of 2026-11-09. Starting point, in the original words: make the results of
Systems42 visible, navigable, most efficient, visually attractive.

Three alternatives follow. Choose one or combine them.


## Alternative A: The answer

> Anyone with a question about a system finds the answer in the Systems42
> dashboard faster than by asking a colleague, and can see where the answer came
> from and how firm it is. The pages are a pleasure to read, so people come back.

Stresses speed and trust. Its weakness is that it says nothing about working
together in a room.


## Alternative B: One shared picture

> The Systems42 dashboard gives everyone working on a system the same picture of
> it: what is wanted and why, who wants it, what has been decided and what is still
> open. It looks good enough to put on the wall in a workshop, and it is clear
> enough that a newcomer can find their way around without an introduction.

Stresses shared understanding, and it comes closest to what has been built so far.
Its weakness is that it does not ask for speed.


## Alternative C: Follow any thread

> Everything Systems42 records about a system can be seen in one place and reached
> from everything it relates to. From any goal you can walk to the requirements
> behind it, the decisions that shaped them and the architecture that answers them,
> and back again, in as few clicks as possible, on pages people enjoy looking at.

Stresses connections, the thing a wiki offers and a document does not. Its weakness
is that it describes the structure more than the benefit to the reader.


## How each covers the four original words

| | Visible | Navigable | Efficient | Attractive |
|---|---|---|---|---|
| **A** | implied | implied | stated, and testable | stated |
| **B** | stated | only for newcomers | barely | stated |
| **C** | stated | stated, the core of it | stated as clicks | stated |


## Recommendation

Alternative A, because it is the only one you can test: hand someone a question and
time them against asking a colleague. Its gap, the workshop, can be closed by the
goals file rather than by the vision. If the dashboard stays a workshop tool (see
open question 1 in `01-stakeholders.md`), take B instead.


## Nitpicks on the original wording

- **"Results of Systems42":** results of what, exactly? Used here to mean what is
  recorded about a system: requirements, architecture, decisions, terms and open
  questions, with their sources. It does not mean the method documentation, though
  the dashboard shows some of that too (`/help`, `/metamodel`).
- **"Visible":** to whom, and when? As built, only to people on the same network
  while someone has the dashboard running.
- **"Most efficient":** a superlative with no comparison can never be checked. It
  also leaves open whose effort is meant. All three alternatives take it to mean the
  reader's time and attention. Alternative A names the comparison: asking a colleague.
- **"Visually attractive":** a matter of taste until someone is named. Alternative B
  makes it concrete: good enough to put on the wall.
- **"Dashboard":** the word promises numbers and gauges at a glance. This one is
  mostly a reference to read and browse. Worth deciding whether the name should stay.


## What the vision leaves out on purpose

- **Editing.** The dashboard only shows the wiki and never changes it. That is a
  firm design choice today, and a vision should not quietly reverse it.
- **The tools behind it.** The vision should still hold if the wiki moved to a
  different format or tool.
- **Numbers.** Targets belong in the goals and quality requirements, where they can
  change without rewriting the vision.
