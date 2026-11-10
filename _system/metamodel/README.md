# metamodel

The wiki's **metamodel, made explicit**: one page per content type, relation,
framework, projection and rule, each with machine-readable frontmatter and a short
human explanation. Before this folder existed the same facts were restated in
`AGENTS.md`, the templates, the dashboard catalog, three dictionaries in the
dashboard app, two req42 docs and the workflows — and drifted (DR-035).

Two levels, deliberately separated:

| Level | Where | Stability | Content |
|-------|-------|-----------|---------|
| **Meta-meta** — the *language* | `meta-metamodel.md` | stable, framework-agnostic | the seven constructs a metamodel is written in: `type`, `relation`, `framework`, `projection`, `anchor`, `altitude-scale`, `rule` — and the frontmatter each one carries |
| **Meta** — the *instances* | `types/`, `relations/`, `frameworks/`, `projections/`, `altitude.md`, `rules/` | specific, grows with the method | the fourteen content types, their fields and relations, the req42 / arc42 / commons blocks, the projections the dashboard renders, the granularity scale |

Reuse in another project: copy the whole folder with `make new` (it is a product
path, DR-031). Adding arc42 means adding `types/` and a `frameworks/fw-arc42.md`
block list — the meta-meta level does not change.

## Reading order
1. `meta-metamodel.md` — the language.
2. `frameworks/fw-req42.md` — which drawers exist and which types live in each.
3. `types/type-*.md` — one page per content type; links to its relations and anchors.
4. `relations/rel-*.md` — one page per frontmatter field that carries wikilinks.
5. `projections/proj-*.md` — the derived views; what they read, never what they store.
6. `altitude.md` — the granularity scale. **Carries an open question** (use case ↔ epic).
7. `rules/` — inspect / relations checks as data (first three extracted; more to follow).

## Consumers
- **Humans and the agent**: this is the explanation of the schema. `AGENTS.md`
  keeps its one-line-per-type table and points here for the rest.
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
- Filenames carry a construct prefix (`type-`, `rel-`, `fw-`, `proj-`, `rule-`) so
  that Obsidian basenames never collide with `_templates/` or `_system/anchors/`.
- Frontmatter keys are the contract (`meta-metamodel.md` lists them); the body is
  explanation and may cite decision records and anchors with wikilinks.
- Universal fields (`id, type, title, status, created, updated, sources, related, tags`)
  are declared once in `meta-metamodel.md`, not repeated on every type page.
- English throughout, like the rest of `_system/`.
