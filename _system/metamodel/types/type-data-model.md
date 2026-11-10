---
type: metamodel
construct: type
name: data-model
aliases: [type-data-model, DM]
prefix: DM
folder: wiki/data-models
template: _templates/data-model.md
label: Data model
label_de: Datenmodell
block: R4
lifecycle: content
stereotypes: [entity, value-object, sum-type]
naming: "entity / value-object / sum-type name"
fields:
  - {name: stereotype, kind: enum, values: [entity, value-object, sum-type], required: true, doc: "DR-019"}
  - {name: parent, kind: link-list, relation: parent, doc: "sum-type variants point at their sum-type"}
  - {name: bounded-context, kind: scalar}
  - {name: source-of-truth, kind: scalar, doc: "system / owner of this data"}
  - {name: relationships, kind: structured-list, relation: relationships, doc: "{verb, target, cardinality, kind, mandatory} — the class diagram reads these (DR-027)"}
anchors: [req42]
projections: [data-model-diagram]
---

# Type: data model

req42 block 05 (supporting models): entities, value objects and sum types with
typed [[rel-relationships]]. The class diagram is a [[proj-data-model-diagram|projection]]
over `relationships`, so the prose attribute list and the diagram cannot disagree.
