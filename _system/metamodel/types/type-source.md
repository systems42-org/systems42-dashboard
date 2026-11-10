---
type: metamodel
construct: type
name: source
aliases: [type-source, SRC]
prefix: SRC
folder: raw/sources
template: _templates/source.md
label: Source
label_de: Quelle
block: null
lifecycle: source
stereotypes: []
naming: "source title"
universal: false
fields:
  - {name: id, kind: scalar}
  - {name: type, kind: scalar}
  - {name: title, kind: scalar}
  - {name: status, kind: enum, values: [ingested]}
  - {name: created, kind: date}
  - {name: updated, kind: date}
  - {name: tags, kind: list}
  - {name: source-type, kind: enum, values: [interview, transcript, document, spec, email, ticket, diagram, observation]}
  - {name: origin, kind: scalar, doc: "raw/ingested/<file> after archiving (DR-008), or author / URL"}
  - {name: captured, kind: date}
  - {name: sha256, kind: scalar, doc: "body hash of the original; inspect checks for drift"}
  - {name: ingested-pages, kind: link-list, relation: ingested-pages}
anchors: []
projections: []
---

# Type: source

The provenance layer, not a wiki type: lives in `raw/sources/`, belongs to no
block, has its own lifecycle and no `sources` / `related` fields. Every wiki claim
points at one through [[rel-sources]]; the source lists the pages it touched in
[[rel-ingested-pages]].
