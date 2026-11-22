# metamodel

The wiki's **metamodel, made explicit**: one page per content type, relation,
framework, projection, notation and rule, each with machine-readable frontmatter and a short
human explanation. Before this folder existed the same facts were restated in
`CLAUDE.md`, the templates, the dashboard catalog, three dictionaries in the
dashboard app, two req42 docs and the workflows — and drifted (DR-035).

Two levels, deliberately separated:

| Level | Where | Stability | Content |
|-------|-------|-----------|---------|
| **Meta-meta** — the *language* | `meta-metamodel.md` | stable, framework-agnostic | the seven constructs a metamodel is written in: `type`, `relation`, `framework`, `projection`, `anchor`, `notation`, `rule` — and the frontmatter each one carries |
| **Meta** — the *instances* | `types/`, `relations/`, `frameworks/`, `projections/`, `notations/`, `rules/` | specific, grows with the method | the content types, their fields and relations, requirement notations and levels, the req42 / arc42 / commons blocks, and the projections the dashboard renders |

Reuse in another project: copy the whole folder with `make new` (it is a product
path, DR-031). Adding arc42 means adding `types/` and a `frameworks/fw-arc42.md`
block list — the meta-meta level does not change.

## Reading order
1. `meta-metamodel.md` — the language.
2. `frameworks/fw-req42.md` — which drawers exist and which types live in each.
3. `types/type-*.md` — one page per content type; links to its relations and anchors.
4. `relations/rel-*.md` — one page per frontmatter field that carries wikilinks.
5. `projections/proj-*.md` — the derived views; what they read, never what they store.
6. `notations/` — one file per functional-requirement notation: its levels, extra fields and anchors, and, as its body, the page template. A project's own notations live in `_system/notations/`.
7. `rules/` — inspect / relations checks as data (first three extracted; more to follow).

## Consumers
- **Humans and the agent**: this is the explanation of the schema. `AGENTS.md`
  keeps its one-line-per-type table and points here for the rest; `CLAUDE.md`
  imports `AGENTS.md` for Claude Code.
- **`_system/scripts/metamodel-lint.py`**: checks every type page against its
  template (field sets must match exactly), every relation against the types it
  names, every framework block against the wiki folders, every projection against
  the fields it reads. Run from the repo root: `python3 _system/scripts/metamodel-lint.py`.
- **Dashboard**: `/metamodel` (≡ menu → Metamodel) renders this folder — the
  types as a network grouped by block, the relations as arrows, and tables with
  each construct's definition, fields and a live example page. Follow-up
  (DR-035 consequence): `catalog.py` and the prefix/folder/label dictionaries
  in `app.py` are to be derived from `frameworks/` and `types/`; today they are
  still hand-maintained and the lint compares them.

## Conventions
- Filenames carry a construct prefix (`type-`, `rel-`, `fw-`, `proj-`, `notation-`, `rule-`) so
  that Obsidian basenames never collide with `_templates/` or `_system/anchors/`.
- Frontmatter keys are the contract (`meta-metamodel.md` lists them); the body is
  explanation and may cite decision records and anchors with wikilinks.
- Universal fields (`id, type, title, status, created, updated, sources, related, tags`,
  and the optional `aliases`) are declared once in `meta-metamodel.md`, not repeated
  on every type page. An `optional: true` universal field may sit on any page; a
  template need not carry it.
- English throughout, like the rest of `_system/`.
