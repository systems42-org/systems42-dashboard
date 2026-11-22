# Issue discussion

A change is discussed in an issue tracker, over days and between several people.
When the discussion settles, its result is summarised into `raw/` and captured.

## When it fits

- The change touches more than one person's work, or more than one repository.
- People are not in the same place at the same time.
- The discussion needs a public trail: who said what, and when.

It fits less well when the group has to decide many small points at once. A
workshop is faster for that.

## Steps

1. **Open an issue** that states the problem and, if there is one, a first proposal.
   Split a large topic into sub-issues, one per point.
2. **Say who works on which point,** in the issue, before anyone starts. A habit,
   not a rule, but it saves duplicate work.
3. **Discuss** in the comments. The agent can draft a status comment or a comparison,
   but the people decide.
4. **Record each decision as a comment** in the issue as it is made. The issue stays
   the place where the decision is.
5. **Summarise into `raw/`.** The agent writes a note that summarises the issue and
   its decisions, with links. The human reads and corrects it.
6. **Grill and capture** the note, as for any source.
7. **Deliver** by the commit policy. Link the issue from the commit or pull request.

## What lands in `raw/`

A summary of the issue: the decision, the rules that follow from it, the scope, and
links to the issue and its comments. When the issue changes later, the note is
updated before it is captured, or a new note follows.

## Who decides, and where it is recorded

The people in the issue. The issue comments are the first record; the note in `raw/`
and its source record are the second. Both name the same decisions.

## Pitfalls

- **Two people work on the same point.** Nobody claimed it, so both started. Claim
  the point in the issue first (step 2).
- **The note and the issue drift apart.** A later comment changes a decision, but the
  note in `raw/` still says the old one. Before the note is captured, correct it.
  After it is captured it is archived and never edited; write a new note for the
  later decision and capture that.
- **The repository moved on.** Pull every repository involved before you compare or
  capture; a colleague may have captured part of it the same day. This too is a team
  habit, whatever tools you use.
- **The discussion never ends.** An issue with no decision after a while is a reason
  for a short call or a workshop.

## Example

In the Systems42 meta repository, the dashboard's requirements had two homes.
[meta #38](https://github.com/systems42-org/meta/issues/38) stated the problem,
the sub-issue [meta #49](https://github.com/systems42-org/meta/issues/49) took one
point, and its comments recorded the comparison and each decision. A note in
`raw/` summarised the issue
([meta SRC-036](https://github.com/systems42-org/meta/blob/main/raw/sources/SRC-036-dashboard-requirements-one-home.md)),
was grilled and captured, and the result went out as
[meta #51](https://github.com/systems42-org/meta/pull/51). The same day, a second
person had worked on the same point without claiming it in the issue, which led to
two competing pull requests.
