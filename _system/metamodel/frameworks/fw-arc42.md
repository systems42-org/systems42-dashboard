---
type: metamodel
construct: framework
name: arc42
aliases: [fw-arc42]
area: architecture
blocks:
  - {id: A1, title: "Solution Strategy", title_de: "Lösungsstrategie", types: [solution-strategy], scope: in}
  - {id: A2, title: "Building Block View", title_de: "Bausteinsicht", types: [building-block], scope: in}
  - {id: A3, title: "Deployment View", title_de: "Verteilungssicht", types: [deployment-node], projections: [deployment-diagram], scope: in}
  - {id: A4, title: "Runtime View", title_de: "Laufzeitsicht", types: [runtime-scenario], scope: in}
  - {id: A5, title: "Crosscutting Concepts", title_de: "Querschnittliche Konzepte", types: [crosscutting-concept], scope: in}
---

# Framework: arc42

The architecture cabinet: A1 [[type-solution-strategy]], A2 [[type-building-block]],
A3 [[type-deployment-node]], A4 [[type-runtime-scenario]], A5
[[type-crosscutting-concept]]. Section 9 (decisions) lives in commons C7.
