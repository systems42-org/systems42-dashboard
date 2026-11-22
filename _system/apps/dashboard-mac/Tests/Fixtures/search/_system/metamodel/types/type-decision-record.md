---
type: metamodel
construct: type
name: decision-record
aliases: [type-decision-record, DR]
prefix: DR
folder: wiki/decisions
template: _templates/decision-record.md
label: Decision record
label_de: Entscheidung
block: C7
lifecycle: content
stereotypes: []
naming: "the decision, as an active statement"
fields:
  - {name: aliases, kind: list, doc: "former IDs, e.g. ADR-0012"}
  - {name: kind, kind: enum, values: [architecture, business, undefined], doc: "`undefined` only when genuinely unclear"}
  - {name: decided, kind: date, doc: "when the decision was taken, not when the page was written"}
  - {name: decision-makers, kind: list, doc: "optional: who decided"}
  - {name: consulted, kind: list, doc: "optional: whose advice was sought"}
  - {name: informed, kind: list, doc: "optional: who was told"}
  - {name: drivers, kind: link-list, relation: drivers, doc: "the requirements this decision rests on (MADR Decision Drivers, linked)"}
  - {name: amends, kind: link-list, relation: amends}
  - {name: superseded-by, kind: link-list, relation: superseded-by, doc: "set together with status: deprecated"}
anchors: [MADR]
projections: []
---

# Type: decision record

A choice among named alternatives that is **cross-cutting**, **expensive to
reverse** and **a real choice** — all three tests from [[MADR]]. A standing rule
or wanted capability is a requirement (FR, QR, CON) instead; a field addition,
rename or naming convention is a `CHANGELOG.md` entry. `kind: architecture`
records are the arc42 section 9 slice; both kinds live in commons block C7.
