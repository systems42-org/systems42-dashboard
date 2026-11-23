---
type: metamodel
construct: relation
name: scope-building-block
aliases: [rel-scope-building-block]
field: scope-building-block
direction: directed
semantics: scope
inverse: use-cases-scoped
inverse_stored: false
reciprocity: none
edges:
  - {from: functional-requirement, to: building-block, cardinality: "0..1", note: "for notation: use-case; alternative to context, exactly one scope target in total"}
  - {from: functional-requirement, to: context, cardinality: "0..1", note: "for notation: use-case; the whole system, alternative to building-block"}
---

# Relation: scope building block

The one system under discussion of a Cockburn use-case requirement: either
a [[type-building-block|building block]] at any level, or the
[[type-context|context]] when the use case covers the whole system. The field
is required and carries exactly one link in total; the two target types are
alternatives, not two separate scopes. No whole-system building-block page
is needed merely to provide a scope target.

Further blocks that take part in or realise the use case are
[[rel-concerns|concerns]] links
([[FR-005-link-a-requirement-to-a-building-block|FR-005]]).
