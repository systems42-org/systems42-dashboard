# Conversation

The decisions come up while you talk to the agent, mostly during a grilling. There is
no file to put into `raw/`; the chat itself is the source.

## When it fits

- You are already grilling a source, and the answers add or change requirements.
- You want to refine existing pages, not add new material.
- When the chat answers refine another source that is being captured, the session is
  recorded as additional provenance next to that source, not instead of it.
- The person in the chat is the one who decides.

## Steps

1. **Grill.** While it stress-tests, the agent asks one question at a time, each with
   its recommended answer. The closing round after the pages are drafted puts every
   question that can be asked now into one numbered message; questions that depend on
   an answer follow in the next round.
2. **Answer.** Short answers are fine; the agent writes the precise wording.
3. **Record the session as a source.** The agent creates a source record without a
   file. Its origin names the person and the date of the chat, and it lists the pages
   the answers touched.
4. **Log the decisions.** Each answer goes into the log entry of the capture, one line
   per question.

## What lands in `raw/`

Only the source record in `raw/sources/`, with no file behind it. The decisions are
in `_system/log.md` and in the history of each page.

## Who decides, and where it is recorded

The person in the chat. The source record says who and when; the log says what.

## Pitfalls

- **The chat is lost and the log is thin.** Then nobody can see later why a page says
  what it says. Write one log line per decision, in words a colleague understands.
- **The agent decides.** A recommended answer is not an answer. If the person does not
  answer, the point becomes an Issue.
- **Other people are affected.** A conversation is one person's decision. If it changes
  someone else's page, tell them, for example in the pull request.

## Example

Grilling sessions in systems42-dashboard are recorded this way, for example the
answers on the shared session
([systems42-dashboard SRC-033](https://github.com/systems42-org/systems42-dashboard/blob/main/raw/sources/SRC-033-grilling-session-on-the-shared-session.md))
and on the requirements moved from meta
([systems42-dashboard SRC-035](https://github.com/systems42-org/systems42-dashboard/blob/main/raw/sources/SRC-035-grilling-session-on-the-requirements-moved-from-meta.md)).
