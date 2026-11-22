---
type: metamodel
construct: type
name: deployment-node
aliases: [type-deployment-node, DN]
prefix: DN
folder: wiki/deployment-nodes
template: _templates/deployment-node.md
label: Deployment node
label_de: Infrastrukturelement
block: A3
lifecycle: content
stereotypes: [environment, host, container, service]
naming: "the node's name as the operators say it"
fields:
  - {name: stereotype, kind: enum, values: [environment, host, container, service], doc: "environment = cloud account, data centre, network zone or stage (production, test); host = server or VM; container = runtime or execution environment; service = third-party or managed service"}
  - {name: parent, kind: link, relation: parent, doc: "the enclosing node; empty = infrastructure level 1"}
  - {name: hosts, kind: link-list, relation: hosts, doc: "the building blocks deployed on this node"}
  - {name: connects, kind: structured-list, relation: connects, doc: "{to, protocol?, note?}: channels to other nodes or external interfaces"}
  - {name: technology, kind: scalar, doc: "optional: product, version, size"}
  - {name: drivers, kind: link-list, relation: drivers, doc: "the requirements this node answers"}
  - {name: decisions, kind: link-list, relation: shaped-by, doc: "the decision records behind this node"}
  - {name: state, kind: enum, values: [outdated, current, planned, target], doc: "outdated = historical, no longer in use; current = in use today; planned = decided, not built yet; target = the intended end state; empty = target"}
  - {name: superseded-by, kind: link, relation: superseded-by, doc: "on a replaced page: its successor"}
anchors: [arc42]
projections: [deployment-diagram, governed-by]
---

# Type: deployment node

arc42 section 7: one element of the technical infrastructure — environment,
host, container or service. Levels via [[rel-parent]], the mapping of software
to infrastructure via [[rel-hosts]], channels via [[rel-connects]]. The
deployment diagram is a [[proj-deployment-diagram|projection]]: one picture of
all states, each marked. Neighbour systems stay [[type-external-interface]]
pages.
