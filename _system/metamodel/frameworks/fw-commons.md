---
type: metamodel
construct: framework
name: commons
aliases: [fw-commons]
area: commons
blocks:
  - {id: C1, number: "06", title: "Quality Requirements", title_de: "Qualitätsanforderungen", types: [quality-requirement], scope: in}
  - {id: C2, number: "07", title: "Constraints", title_de: "Randbedingungen", types: [constraint], scope: in}
  - {id: C3, number: "03", title: "Scope & Context", title_de: "Scope und Kontext", types: [context, external-interface], scope: in}
  - {id: C4, number: "02", title: "Stakeholders", title_de: "Stakeholder", types: [stakeholder], scope: in}
  - {id: C5, number: "08", title: "Domain Terms", title_de: "Domänenterminologie", types: [glossary-term], scope: in}
  - {id: C6, number: "12", title: "Issues", title_de: "Offene Punkte", types: [issue], scope: in, note: "Issues, especially kind: risk, plus [!assumption] markers"}
  - {id: C7, title: "Decisions", title_de: "Entscheidungen", types: [decision-record], scope: in, note: "decision records of kind architecture, business or undefined; arc42 section 9 is their architecture slice"}
---

# Framework: commons

The drawers req42 and arc42 **share** ("some drawers are managed jointly" —
Hruschka). `number` is the req42 block number; the arc42 counterpart sections are
1 (goals/constraints/quality), 2 (constraints), 3 (context), 10 (quality), 11
(risks), 12 (glossary).
