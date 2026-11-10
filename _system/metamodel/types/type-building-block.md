---
type: metamodel
construct: type
name: building-block
aliases: [type-building-block, BB]
prefix: BB
folder: wiki/building-blocks
template: _templates/building-block.md
label: Building block
label_de: Baustein
block: A2
lifecycle: content
stereotypes: []
naming: "the block's name"
fields:
  - {name: parent, kind: link, relation: parent, doc: "the enclosing block; empty or a [[type-context|context]] page = level 1"}
  - {name: drivers, kind: link-list, relation: drivers, doc: "the requirements this block answers (arc42 black box: fulfilled requirements, quality characteristics)"}
  - {name: decisions, kind: link-list, relation: shaped-by, doc: "the decision records that shaped this block"}
  - {name: uses, kind: link-list, relation: uses, doc: "static dependencies on other blocks or external interfaces — the arrows of the white box"}
  - {name: location, kind: scalar, doc: "optional: directory / module / package in the code"}
  - {name: state, kind: enum, values: [outdated, current, planned, target], doc: "outdated = historical, no longer in use; current = in use today; planned = decided, not built yet; target = the intended end state; empty = target"}
  - {name: superseded-by, kind: link, relation: superseded-by, doc: "on a replaced page: its successor"}
anchors: [arc42]
projections: [bb-tree, whitebox, deployment-diagram, sequence-diagram, governed-by]
---

# Type: building block

arc42 section 5, the Building Block View: one page per block, described as a
**black box** (purpose, interfaces, quality, open issues). Levels come from
[[rel-parent]]; a block's **white box** — its children and their [[rel-uses]]
arrows — is a [[proj-whitebox|projection]], never drawn by hand. A block names the
glossary terms it implements in `related:`; the requirements it answers in
[[rel-drivers]].
