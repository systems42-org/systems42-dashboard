# Interview or transcript

You talk to one stakeholder, or record a meeting. The transcript or the notes go
into `raw/` and are captured.

## When it fits

- You need what one person knows, in their words: a domain expert, a user, a sponsor.
- A meeting was recorded and the recording or its transcript exists.
- You want the original wording kept, so later questions can go back to it.

## Steps

1. **Ask for consent** to record, and agree what may be kept.
2. **Run the interview,** or record the meeting.
3. **Prepare the source.** Transcribe it, or let a tool do so. Remove what must not
   be kept, such as names of customers or personal data, before the file enters
   `raw/`. What is in `raw/` is kept for good.
4. **Put the source into `raw/`** as it is: the transcript, or the recording if
   there is no transcript yet. Whatever you put in is the original; the capture
   records and hashes it. A transcript or markdown copy the agent derives during the
   capture is working material and leaves the original untouched.
5. **Grill and capture.** The agent separates decisions, requirements, ideas and open
   points, and asks the closing round.
6. **Go round again or go back.** An answer that opens a new question leads to a
   further round. What only the interviewee can answer goes back to them; what the
   requirements owner declines, defers or cannot answer becomes an Issue.

## What lands in `raw/`

The transcript or the interview notes, after redaction, with the date and the
people. An audio or video file may stay beside it as the original.

## Who decides, and where it is recorded

The interviewee says what they want; the people who own the requirements decide what
the wiki records. The transcript is the record of what was said, the closing round
and the log of what was decided from it.

## Pitfalls

- **What was said is taken as decided.** An interviewee's wish is a source, not an
  agreement. Several interviews may contradict each other; the agent puts the
  contradiction to the requirements owner and never picks a side. Only if the owner
  does not decide it becomes an Issue that links both sides.
- **Something sensitive reaches `raw/`.** Redact first. `raw/` is never edited.
- **The transcript is too long to grill in one go.** Split it by topic and capture
  the parts one at a time.

## Example

No interview has been captured in the Systems42 meta repository yet. What it has
are requirements for supporting this pattern: capture a
meeting transcript or minutes
([meta FR-014](https://github.com/systems42-org/meta/blob/main/wiki/functional-requirements/FR-014-capture-a-meeting-transcript.md)),
and prepare and redact a meeting source before it enters `raw/`
([meta FR-015](https://github.com/systems42-org/meta/blob/main/wiki/functional-requirements/FR-015-prepare-and-redact-a-meeting-source-before-it-enters-raw.md),
rated Won't for now).
