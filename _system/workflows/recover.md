# Workflow: Recover

Recover the abstractions of existing code into a report that Capture can
take in. The code already says what the system does, and its comments say
how. Recover adds what neither says: the capabilities, boundaries, building
blocks and qualities the code implements (see [[DT-026-abstraction]]). It
writes no wiki pages. Alias: archeology. See [[DT-025-recover-loop]],
[[ACT-005-recover]] and [[FR-035-recover-requirements-and-architecture-from-existing-code]].

## The loop

1. **Scope.** The human names the scope: a repository, or a path in one.
   They may name one feature or building block to go one level deeper.
   Without that, the depth is level 1. If they ask for more depth across the
   whole scope, decline and ask them to name one element.
2. **Wiki first.** Read `_system/index.md` and the pages that touch the
   scope. Note which levels are rich and which are thin or empty. Dig where
   the wiki is thin; where it is rich, compare instead of re-deriving.
3. **Pin the revision.** Record the repository and the commit you read
   (`git rev-parse HEAD`). Every finding refers to that commit. If the working
   tree has uncommitted changes in the scope, say so in the report.
4. **Work top-down.** Go through the levels in this order and stop at the
   depth limit:
   1. **Goals, stakeholders, rationale.** Never derive them. Where the code
      hints at one, write a question.
   2. **Context and external interfaces.** The real external systems the
      code talks to, and in which direction data flows.
   3. **Constraints.** Limits the code obeys: technology, operation, licence,
      platform.
   4. **Quality hints.** Only candidate scenarios. The measure is a gap.
   5. **Level-1 building blocks.** Black boxes and their `uses:`.
   6. **Features.** What a user can do, named as capabilities.
   7. **One level deeper, only for the named element:** stories under the
      feature, or level-2 blocks inside the block. If the code cannot settle
      how a block divides, that is a gap, not a proposed split.

   Do not write decision records: code shows only the option that was
   chosen. Ask why instead.
5. **Write abstractions, not copies.** Every finding passes the tests of
   [[DT-026-abstraction]]. It survives a refactoring that keeps the
   behaviour, it names what and why rather than how, and it is shorter than
   the code it stands for. Code names, paths and routes may appear only as
   evidence. A finding that fails is lifted to the capability it serves, cut,
   or reported as a missing abstraction.
6. **Label the evidence.** Every finding carries one label:
   - **observed:** a check ran and showed it;
   - **read:** inferred from reading the code;
   - **assumed:** a guess, to be confirmed.
7. **Check every constraint you touch.** Run at least one check that
   supports or refutes it: a test, a command, a request against the running
   code. If none can run, say why. Keep check scripts out of the scope's
   repository.
8. **Resolve cited IDs.** Collect the requirement IDs cited in the code and
   in documentation written alongside it. Resolve each against the right
   wiki. Report every **wrong** (resolves to a different requirement),
   **foreign** (belongs to another wiki) and **dangling** (resolves nowhere)
   reference. Such documentation is a trace claim, not independent evidence
   of intent.
9. **Compare with the wiki.** Classify each finding as **covered**,
   **missing** or **in conflict**. Text search is a weak oracle; read the
   page before calling a finding covered. A conflict is reported for a human
   decision, never resolved.
   **Delivery candidates:** list every feature the code shows as built while
   no story under it records a delivery state. Each is a candidate for a
   backfill run of [[ACT-004-implement|Implement]], which checks the stories
   criterion by criterion. Recover never sets a delivery state: a *read*
   finding is not a checked criterion. If the wiki's metamodel has no
   delivery fields, say so.
10. **Write the report** to the `raw/` inbox of the wiki the scope belongs
    to, as `recovery-<repository>-<short-commit>.md`, using the skeleton
    below. No wiki page changes in a Recover run.
11. **Closing round, one gap at a time.** Unlike Capture's closing round,
    ask **one gap per message**, top-down from goals and context to features
    and building blocks, and wait for the answer before the next. The point
    is the human's knowledge, not their approval of your guesses:
    - **Intent** (a goal, a stakeholder, a rationale, a measure or target,
      whether observed behaviour is wanted): ask an **open question**. Say
      what the code shows, and list the existing pages that **may apply**
      (stakeholders, goals, constraints, requirements, issues), each as a
      link to its file. They are your search result, not existing links:
      label them so. Name them as candidates only where they fit well;
      otherwise leave the question fully open. Never invent a candidate.
    - **Choice** (how to capture a finding, between named options): list
      the options and recommend one.

    After each answer, rephrase or drop later gaps it settles. Look facts up
    instead of asking.
12. **Record the answers** in the report: each answered gap shows the
    human's answer; each unanswered or deferred gap stays marked **open**.
    When the human hands the report to Capture, it is not edited again. Its
    open gaps are asked in Capture's closing round or become Issues.

## Report skeleton

```markdown
---
title: Recovery report — <repository> <short-commit>
author: agent (<harness and model>), for <human>
date: YYYY-MM-DD
repository: <name or URL>
revision: <full commit hash>
scope: <repository, or path in it>
depth: level 1 | level 1, deeper for <feature or block>
---

# Recovery report — <repository> <short-commit>

## Scope and evidence
What was read, what was not, which checks ran.

## Goals and stakeholders
Questions only.

## Context and external interfaces
## Constraints
## Quality hints
## Building blocks (level 1)
## Features
## One level deeper: <element>        (only if requested)
## Cited requirement IDs
## Comparison with the wiki
Covered · missing · in conflict.

## Delivery candidates
Features that look built while no story under them records delivery.

## Gaps
Numbered, top-down. Each: **intent** or **choice**, the question, for a
choice the options and the recommended one, the existing pages that
**may apply** as links, and after the closing round **Answer:** <answer>
or **Open**.
```

Each finding names its evidence label and its evidence (file, command,
check result) after the abstraction, never instead of it.

## Stop conditions

- Do not write wiki pages; Capture does that.
- Do not derive goals, stakeholders or decision rationale.
- Do not go deeper than the depth limit.
- Do not edit the report after the human has handed it to Capture.
