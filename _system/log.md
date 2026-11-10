# Log

Append-only. One entry per operation. Keep the prefix exact so the log is
greppable: `grep '^## \[' _system/log.md | tail -5`.

<!-- Format (indented so the grep above does not match it):
    ## [YYYY-MM-DD] <op> | <subject>
    - Source / scope, grill gate, created, updated, issues, open questions
-->

## [2026-11-10] new-project | Systems42 Dashboard
- Created with `_system/scripts/new-project.sh new` from atrium-main @ ec95003.
- Product paths copied (schema, templates, anchors, workflows, skills, dashboard, docs). No decision records are inherited: `wiki/decisions/` starts empty and this project's own decisions start at DR-001.
- `wiki/` and `raw/` start empty. Next step: `_system/workflows/bootstrap.md`.
