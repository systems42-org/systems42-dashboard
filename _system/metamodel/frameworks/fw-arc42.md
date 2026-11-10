---
type: metamodel
construct: framework
name: arc42
aliases: [fw-arc42]
area: architecture
blocks:
  - {id: A1, title: "Solution Strategy", title_de: "Lösungsstrategie", types: [], scope: planned}
  - {id: A2, title: "Building Block View", title_de: "Bausteinsicht", types: [building-block], scope: in}
  - {id: A3, title: "Deployment View", title_de: "Verteilungssicht", types: [deployment-node], scope: in}
  - {id: A4, title: "Runtime View", title_de: "Laufzeitsicht", types: [runtime-scenario], scope: in}
  - {id: A5, title: "Crosscutting Concepts", title_de: "Querschnittliche Konzepte", types: [concept], scope: in}
---

# Framework: arc42

The architecture cabinet. A2 (Building Block View) holds [[type-building-block]],
A3 (Deployment View) [[type-deployment-node]], A4 (Runtime View)
[[type-runtime-scenario]], A5 (Crosscutting Concepts) [[type-concept]]. Every
architecture page carries `state: current | target`, so today's landscape and the
target live side by side (DR-010). A1 stays `scope: planned`. Section 9 (decisions) lives in commons C7.
