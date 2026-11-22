---
type: metamodel
construct: projection
name: deployment-diagram
aliases: [proj-deployment-diagram]
reads:
  - {type: deployment-node, fields: [parent, hosts, connects, state, superseded-by]}
  - {type: building-block, fields: []}
  - {type: external-interface, fields: []}
output: mermaid
stored: false
implemented: "/arc42/deployment, /page/deployment-nodes/<DN> (subtree)"
anchor: arc42
---

# Projection: deployment diagram

Nodes nested by [[rel-parent]], the blocks they [[rel-hosts|host]] inside them,
[[rel-connects]] as edges labelled with the protocol. One diagram of all states:
`current` plain, `planned` and `target` dashed, `outdated` grey, a dotted edge to
the successor. Never stored.
