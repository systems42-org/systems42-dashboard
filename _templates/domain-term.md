---
id: DT-NNN
type: domain-term
title: <Term>
status: draft
created: {{date}}
updated: {{date}}
sources: []
related: []
tags: [domain-term]
aliases: []
bounded-context: <context name>
agreed: false
stereotype:            # optional: entity | value-object | sum-type
parent: []             # sum-type variants link to their sum type
source-of-truth:       # entity only
attributes: []         # structured terms only
#  - {name: <name>, type: <type>, multiplicity: "0..1", identifier: false}
relationships: []      # structured terms only
#  - {to: "[[DT-...]]", label: <contains>, kind: composition, multiplicity: "1..*"}
# kind: association | aggregation | composition | generalization
# multiplicity applies at the target end and is omitted for generalization
# a structured term can refer to itself, except through generalization
---

# {{title}}

**Definition.** <One canonical sentence.>

**In context.** <Where this meaning applies.>

**Distinguish from.** <Related terms and how they differ.>

<!-- Optional for structurally modelled terms. -->

**Identity.** <What identifies an entity.>

**Attributes.** <Notes on attributes listed in frontmatter.>

**Invariants / rules.**
- <Business rule.>
