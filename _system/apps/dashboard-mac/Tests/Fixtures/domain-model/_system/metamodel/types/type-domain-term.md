---
type: metamodel
construct: type
name: domain-term
aliases: [type-domain-term, DT]
prefix: DT
folder: wiki/domain-terms
template: _templates/domain-term.md
label: Domain term
label_de: Domänenbegriff
block: C5
lifecycle: content
stereotypes: [entity, value-object, sum-type]
naming: One canonical term per meaning and bounded context.
fields:
  - {name: bounded-context, kind: scalar}
  - {name: agreed, kind: bool}
  - {name: stereotype, kind: enum, values: [entity, value-object, sum-type], required: false}
  - {name: parent, kind: link-list, relation: parent, doc: "sum-type variant to sum type"}
  - {name: source-of-truth, kind: scalar, doc: "entity only"}
  - {name: attributes, kind: structured-list, doc: "{name, type, multiplicity, identifier}"}
  - {name: relationships, kind: structured-list, relation: relationships, doc: "{to, label, kind, multiplicity}"}
anchors: [req42]
projections: [terminology-graph, entity-diagram]
---

# Type: domain term

A definition records a meaning in the domain. An optional stereotype allows
the same page to carry attributes and typed relationships. [[rel-related]]
applies to all terms. See DR-039.
