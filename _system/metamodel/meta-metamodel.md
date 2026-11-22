---
type: metamodel
construct: meta-metamodel
name: meta-metamodel
aliases: [meta-metamodel, metamodel-language]
version: 0.1
universal_fields:
  - {name: id,      kind: scalar, doc: "TYPE-NNN, stable, never reused"}
  - {name: type,    kind: scalar, doc: "the type page's `name`"}
  - {name: title,   kind: scalar, doc: "the page title, in the wiki's ubiquitous language"}
  - {name: status,  kind: enum,   doc: "per the type's `lifecycle`"}
  - {name: created, kind: date}
  - {name: updated, kind: date}
  - {name: sources, kind: link-list, relation: sources}
  - {name: related, kind: link-list, relation: related}
  - {name: tags,    kind: list}
  - {name: aliases, kind: list, optional: true, doc: "other names for the page (Obsidian aliases); any page may carry it, a template need not"}
lifecycles:
  content: [draft, review, accepted, deprecated]
  issue:   [open, in-progress, resolved, wontfix]
  source:  [ingested]
field_kinds: [scalar, enum, bool, int, date, timestamp, list, link, link-list, structured-list]
constructs: [type, relation, framework, projection, anchor, notation, rule]
---

# The meta-metamodel — the language a metamodel is written in

Everything in `_system/metamodel/` is an instance of one of **seven constructs**.
The constructs are generic: they know nothing about req42, arc42, epics or use
cases. A metamodel for a different method would reuse them unchanged. Each
construct is a markdown page whose **frontmatter is the contract** and whose body
explains. Shared frontmatter on every page: `type: metamodel`, `construct:`,
`name:`, `aliases:`.

## 1. `type` — a content unit
A kind of page the wiki stores: one folder, one template, one ID prefix.

| key | meaning |
|-----|---------|
| `name` | the value instances carry in `type:` |
| `prefix` | ID prefix, e.g. `FR` |
| `folder` | where instances live, e.g. `wiki/functional-requirements` |
| `template` | the `_templates/` file instances are written from |
| `label`, `label_de` | English and German display names |
| `block` | the framework block it belongs to (`R3`, `C4`, …) or `null` |
| `lifecycle` | which status list applies: `content`, `issue`, `source` |
| `stereotypes` | closed list of sub-kinds inside the one type, or `[]` |
| `naming` | title grammar, in words |
| `universal` | `true` (default) ⇒ carries the universal fields (an `optional` one, like `aliases`, may be left out of the template); `false` ⇒ lists every field itself |
| `fields` | the type-specific frontmatter fields: `{name, kind, values?, required?, relation?, doc}` |
| `anchors` | the `_system/anchors/` standards applied to instances |
| `projections` | the projections that read this type |

A field whose `kind` is `link` or `link-list` names the `relation` it instantiates.
Prose wikilinks in the body are untyped edges and are not declared.

## 2. `relation` — a frontmatter field that carries wikilinks
| key | meaning |
|-----|---------|
| `field` | the frontmatter key |
| `direction` | `directed` or `symmetric` |
| `semantics` | one word: `hierarchy`, `association`, `provenance`, `serves`, `actor`, `beneficiary`, `structure`, `origin`, `revision`, `rationale`, `dependency`, `interaction` |
| `inverse` | the name of the reverse reading (e.g. `children`) |
| `inverse_stored` | `false` ⇒ the reverse is a **projection**; `true` ⇒ stored as `inverse_field` on the target |
| `reciprocity` | `enforced` (the relations linter repairs missing back-links) or `none` |
| `edges` | `{from, to, cardinality, note?}` — the type pairs this field may connect; `to: any` allowed |

The rule from `_system/workflows/relations.md` lives here as data: only a
`symmetric` relation gets its reverse side repaired; a `directed` one never does.

## 3. `framework` — a cabinet of blocks
A method's drawers (req42, arc42, or the commons they share). Each block names the
types that live in it and whether it is captured.

| key | meaning |
|-----|---------|
| `area` | the dashboard area key (`requirements`, `architecture`, `commons`) |
| `blocks` | `{id, number?, title, title_de?, types, projections?, scope}` with `scope` ∈ `in` (captured), `out` (deliberately not), `planned` |

Every wiki folder belongs to exactly one block across all frameworks.

## 4. `projection` — a derived view
Something rendered from pages and never stored (context diagram, story map, goal
coverage). Declaring what it **reads** is what makes "no drift by construction" checkable.

| key | meaning |
|-----|---------|
| `reads` | `{type, fields}` — the fields the projection depends on |
| `output` | `mermaid`, `table`, `nested-list`, `matrix`, `graph` |
| `stored` | always `false`; a projection that gets persisted has become a type |
| `implemented` | `none` or the dashboard route |
| `anchor`, `decision` | method and decision-record references; `decision` names full stems (`DR-013-…`), never bare IDs, because projects number their own decisions |

## 5. `anchor` — a standard applied to instances
Already exists as `_system/anchors/` (frontmatter `type: anchor`, `applies-to`).
The metamodel does not duplicate anchors; type pages reference them by alias.

## 6. `notation` — a writing form and its levels
A subclass of a type: it adds fields and defines the page body. One file per
notation is both the definition and the page template, so there is no second
copy. Built-in notations ship in `_system/metamodel/notations/`; a project's
own live in `_system/notations/`, which sync never overwrites and harvest never
carries back. A new notation needs no change to the metamodel (DR-038).

| key | meaning |
|-----|---------|
| `name` | the value pages carry in `notation:`; unique across both folders |
| `extends` | the type it specializes, e.g. `functional-requirement` |
| `levels` | ordered list, coarse → fine; the values pages carry in `level:`; not the depth in the `parent:` graph |
| `fields` | extra frontmatter fields, same shape as a type's `fields`; never one the type already declares |
| `anchors` | checklists: a name for every level, or `{name, levels}` for some |
| `implementable_levels` | the levels that are implemented directly and may carry `delivery` (FR-031) |
| `delivery_states` | the `delivery` values this notation allows; `partial` only where a requirement is built in slices (use case) |
| `summary` | one line for the `/metamodel` page |
| body | the page template; each block starts with `<!-- levels: … -->`, and a page keeps only the blocks naming its level |

`default_notation` in `_system/wiki.yaml` names the notation new requirements
get; unset, it is `agile`.

## 7. `rule` — a check as data
What `inspect.md` and `relations.md` describe in prose: where it applies, what it
tests, how sure the check is, and what the agent may do about it.

| key | meaning |
|-----|---------|
| `applies_to` | `{type, notation?, level?}` |
| `check` | the condition, in words precise enough to implement |
| `confidence` | `high`, `medium`, `low` |
| `action` | `auto-fix`, `ask`, `issue` — advisory enforcement, the human decides |
| `source` | the workflow / anchor checklist the rule was extracted from |

## What the meta-meta level deliberately leaves out
Routes, colours, nav labels, tile layouts: those are the dashboard's presentation
of the metamodel and stay in the dashboard (systems42-org/systems42-dashboard),
which reads `frameworks/`; the metamodel never depends on it (meta #40).
