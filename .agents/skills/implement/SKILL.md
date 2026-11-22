---
name: implement
description: >
  Implement a human-selected functional requirement through a readiness check,
  approved plan, criterion-by-criterion evidence, Git delivery tracking and a
  human-reviewed pull request. Use when the user asks to implement or build an
  FR or a slice of a use-case requirement.
argument-hint: "<FR-NNN or requirement title>"
---

# Implement a requirement

Run `_system/workflows/implement.md` in full for one selected requirement or
one use-case slice.

1. Resolve the requested ID/title in `wiki/functional-requirements/`. Ask the
   human which page they mean only if it matches more than one.
2. Read the full page and the relevant related requirements, Issues, quality
   requirements and constraints before assessing readiness.
3. Present the readiness assessment and concrete plan as described by the
   workflow. Wait for explicit human approval of that plan before editing any
   deliverable.
4. Keep a criterion-by-criterion result/evidence table through implementation;
   a passing test suite alone is not enough to claim coverage.
5. Stop at a PR for human review and merge.
