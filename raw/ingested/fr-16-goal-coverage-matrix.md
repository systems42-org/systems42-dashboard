# Goal coverage matrix

Raised by Gernot Starke on 2026-11-13. Written up by Claude for inspection. Not captured, nobody has agreed it yet.

**Requirement.** At the bottom of Vision & Goals, a matrix shows which functional requirements serve which goal. A reader sees at a glance which goals nothing serves yet, and which requirements serve no goal.

**Serves.** Open, see the questions at the end.

**For.** Product owners, business analysts, people presenting Systems42.

## Needs

- One row per goal (objective). One column per functional requirement that names a goal, plus the use cases.
- A mark where a requirement serves a goal. The mark follows the `goal:` field of the requirement. A story or feature with an empty `goal:` serves the goals of its parent.
- Requirements with `goal: []` (enablers) form their own group of columns on the right, set apart.
- A goal row without any mark stands out, so a goal that nothing serves is easy to see.
- Each column shows the requirement's real ID (`FR-024`, `UC-003`), never a made-up label. Hover or focus shows its title. A click opens the requirement.
- Each row's goal links its goal page.
- The matrix stays inside its own box. With many columns it scrolls inside that box, the goal column stays put, and the page never scrolls sideways (QR-001).
- Every mark is also reachable as text on the same page: each goal card lists the requirements that serve it.
- The "Agreed only" filter of the lists applies here too (FR-022): only agreed goals and requirements.

## Success metric(s)

- On a test wiki with 7 goals and 60 requirements, the page does not scroll sideways at 320 and at 1280 CSS pixels, and every goal stays readable while the columns scroll.
- For every mark in the matrix, the requirement's page names that goal, and the other way round.
- A goal with no requirement is visibly marked as such.

## Scope

- **In:** goals against functional requirements and use cases.
- **Out:** quality requirements and constraints in the matrix, coverage percentages, editing.

## Questions for you

1. Answered: GOAL-004 "Requirements with their reasons and their checks".
2. Answered by Systems42, not here (CON-004): the projection `proj-goal-coverage` sets rows and columns, goals against epics and use cases. Enablers are epics in the platform or display lane. A backbone epic with `goal: []` breaks `rule-fr-traces-to-goal` and is marked as such, not counted as an enabler.
3. Answered: no count per row.
4. Answered: only on Vision & Goals. The matrix is a feature under FR-017, Should.
