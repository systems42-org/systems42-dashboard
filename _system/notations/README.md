# Project-specific requirement notations

A project's own functional-requirement notations live here, one file each
(FR-023, DR-038). Start from a copy of a shipped notation in
`_system/metamodel/notations/` and change it. Like those, each file is both the
definition (`type: metamodel`, `construct: notation`, `name`, `extends`,
`levels`, `fields`, `anchors`) and the page template (its body, cut into blocks
by `<!-- levels: … -->` markers). The name must not clash with a shipped
notation. `python3 _system/scripts/metamodel-lint.py` checks it.

To make a notation the default for new requirements, set `default_notation:`
in `_system/wiki.yaml`; unset, the default is `agile`.

`make sync` refreshes only this README and never overwrites, adds or deletes a
notation here; `make harvest` never carries these files back to Systems42.
