---
type: metamodel
construct: type
name: glossary-term
aliases: [type-glossary-term, GLO]
prefix: GLO
folder: wiki/glossary
template: _templates/glossary-term.md
label: Glossary term
label_de: Begriff
block: C5
lifecycle: content
stereotypes: [entity, value-object]
naming: "the term itself, in the ubiquitous language; other-language names in aliases"
fields:
  - {name: aliases, kind: list, doc: "synonyms and other-language names; Obsidian resolves links through them"}
  - {name: bounded-context, kind: scalar, doc: "DDD: where this meaning holds"}
  - {name: agreed, kind: bool, doc: "true once stakeholders confirmed the definition"}
  - {name: stereotype, kind: enum, values: [entity, value-object], required: false, doc: "optional: marks the term as data, drawn as a <<term>> stub in the class diagram until a DM page exists (DR-027)"}
anchors: [req42]
projections: [data-model-diagram]
sort_orders:
  - {label: "A to Z", keys: [title]}
---

# Type: glossary term

req42 block 08, the ubiquitous language: one canonical meaning per term per
bounded context. A term and a data-model entity with the same slug are the **same
concept** and must link each other through [[rel-related]] (relations tier 1).
