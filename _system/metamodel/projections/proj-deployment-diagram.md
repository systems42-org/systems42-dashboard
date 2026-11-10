---
type: metamodel
construct: projection
name: deployment-diagram
aliases: [proj-deployment-diagram]
reads:
  - {type: deployment-node, fields: [parent, hosts, connects, state]}
  - {type: building-block, fields: []}
  - {type: external-interface, fields: []}
output: mermaid
stored: false
implemented: "/arc42/deployment (all nodes, all states), /page/deployment-nodes/<DN> (subtree)"
anchor: arc42
---

# Projection: deployment diagram

Nodes nested by [[rel-parent]], the blocks they [[rel-hosts|host]] inside them,
[[rel-connects]] as edges labelled with the protocol. **One** diagram of all
states. Marks: `current` plain; `planned` and `target` dashed (when the diagram
also shows others); `outdated` or `status: deprecated` grey; a dotted *replaced
by* edge to the successor. Label suffixes (`· planned`, `· outdated` …) say the
same without colour. A node page draws its own subtree the same way. A connection's `note` follows its protocol on the edge label.
Nothing is dropped silently: a `connects:` entry that is not a mapping or names
no page and a `hosts:` entry that is not a building block each show as a hint on the A3 view and the node page.
