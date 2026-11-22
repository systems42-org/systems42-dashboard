---
id: FR-NNN
type: functional-requirement
title: <Name>
status: draft
created: {{date}}
updated: {{date}}
sources: []
related: []
tags: [functional-requirement]
notation: agile       # explicit choice, else `default_notation` in wiki.yaml, else agile
level: story          # one of the notation's ordered levels
parent: []            # [[FR-...]]; graph edge independent of notation level
building-blocks: []   # [[BB-...]] the blocks this requirement concerns (assignment, FR-005)
priority: Should      # Must | Should | Could | Won't ([[MoSCoW]])
release: unscheduled
lane: backbone
order:
goal: []
delivery:             # optional; partial | implemented | outdated | removed
delivery-checked:     # optional ISO 8601 timestamp with timezone
---

<!-- The body comes from the notation, not from this file: the shared
     frontmatter above plus the body of `_system/metamodel/notations/notation-<notation>.md`
     (or `_system/notations/<notation>.md` for a project notation). Copy that
     file's body from `# {{title}}` on, keep only the blocks whose `levels:`
     marker comment names this page's level, and drop the markers.
     The notation also adds its own frontmatter fields (e.g. `primary-actor`
     and `scope-building-block` for use-case). `parent:` is a graph and may
     skip levels. Title language: the wiki's ubiquitous language (AGENTS.md).
     Leave `delivery` and `delivery-checked` blank: only an Implement run sets
     them, and only on levels the notation lists in `implementable_levels`. -->
