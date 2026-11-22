---
type: metamodel
construct: type
name: quality-requirement
aliases: [type-quality-requirement, QR]
prefix: QR
folder: wiki/quality-requirements
template: _templates/quality-requirement.md
label: Quality requirement
label_de: Qualitätsanforderung
block: C1
lifecycle: content
stereotypes: []
naming: "the required quality, noun phrase"
fields:
  - {name: dimensions, kind: list, values: [reliable, flexible, maintainable, efficient, usable, safe, secure, suitable, operable], doc: "Q42 dimensions, one or more (DR-003)"}
  - {name: priority, kind: enum, values: [must, should, could, wont], doc: "MoSCoW"}
  - {name: testable, kind: bool, doc: "true once the measure is verifiable; false ⇒ inspect raises an Issue"}
anchors: [MoSCoW, req42, Q42]
projections: []
---

# Type: quality requirement

req42 block 06: one or more [[Q42]] dimensions plus a Q42 quality scenario ([quality.arc42.org](https://quality.arc42.org)) (stimulus,
response, measure). Shared with arc42 (commons block C1).

arc42's *quality goals* (section 1.2) are not a separate concept here: a quality
goal is a quality requirement, and the most important ones are those with the
highest `priority`.

The dimensions are Q42's nine: reliable, flexible, maintainable, efficient,
usable, safe, secure, suitable, operable. They overlap by design, so a
requirement carries every dimension it touches. ISO 25010's single attribute in
a strict hierarchy is not used (DR-003).
