# Golden data

What the Go dashboard answers on each fixture in `Tests/Fixtures/`. The Swift
core must produce the same data. Tests read these files and never start Go.

Regenerate on purpose only, in a pull request of its own, after the fixtures
or the dashboard changed:

    _system/apps/dashboard-mac/scripts/export-golden.sh

The script needs Go and Python 3. CI never runs it. Two runs give the same
bytes: keys are sorted, lists are sorted or in the order the dashboard shows,
and no time, port, token, host or absolute path is stored. After a run, check
that `git status` shows no change under `Tests/Fixtures/`.

## Files per fixture

`Tests/Golden/<fixture>/`

| File | Content | Source |
|---|---|---|
| `search.json` | The answer of `/search.json`, unchanged. | `/search.json` |
| `pages.json` | Per page id: `id`, `title`, `status`, `type` (the label, such as "Domain term"), `links_to` and `linked_from` (sorted ids). | Detail page of each page in `search.json`, its "Links to" and "Linked from" lists |
| `sections.json` | Per section id (R1 to R6, C1 to C7, A1 to A5): `title`, `area` (`req42`, `commons`, `arc42`), `folders` (sorted), `pages` (sorted ids). Every page is in exactly one section. | Tiles of `/req42`, `/commons`, `/arc42`, folders from `/metamodel`, pages from each tile's list page |
| `metamodel.json` | `version`, `types`, `relations`, `frameworks`, `projections`, `rules`, `anchors`, `language`. Types, relations, projections and rules keep the order of the page. | `/metamodel` |
| `diagrams/<name>.mmd` | Mermaid text, byte for byte. | see below |
| `diagrams/<name>.json` | Cytoscape data block, keys sorted. | see below |

Example `pages.json` entry:

    "DT-001": {"id": "DT-001", "title": "Book", "status": "accepted",
               "type": "Domain term", "links_to": ["DT-002"], "linked_from": ["FR-003"]}

## Extraction rules

The dashboard offers HTML for most of this. The script parses it and reads:

- `pages.json`: title from `h1.page-h1`, status from the status badge of
  `.detail-head`, ids from the `<code>` of each `.rel-block` list item. The
  type label comes from `search.json`, because a requirement page shows
  its notation and level in that place.
- `sections.json`: a tile is `.tile` with id `tile-<id>`. Its list page is the
  tile's link. A page belongs to the section whose folders hold its folder,
  found by its `/page/<folder>/<stem>` or `/functional-requirements/<stem>` link.
- `metamodel.json`: one entry per table row of the sections Content types,
  Relations, Projections, Rules and Anchors, and the Version and Language
  sections. Text is whitespace-normalised. `type`, `relation` and
  `applies_to` values are the type names, such as `functional-requirement`.
  `version.state` is `supported`, `unsupported` or `missing`. The dashboard
  version number is left out, it changes every release. A type's `example`
  is the page the dashboard picks (most mature of that type).

## Diagrams

A route gives `<name>.mmd` for each `pre.mermaid` block (`<name>-2.mmd` for a
second one) and `<name>.json` for each JSON script block.

| Name | Route |
|---|---|
| `context` | `/req42/scope` |
| `data-model` | `/entity-diagram` |
| `models` | `/req42/models` |
| `goals`, `goal-matrix.json` | `/goals` |
| `story-map` | `/req42/functional-requirements` |
| `building-blocks` | `/arc42/building-blocks` |
| `deployment` | `/arc42/deployment` |
| `runtime`, `strategy`, `concepts` | `/arc42/runtime`, `/arc42/strategy`, `/arc42/concepts` |
| `term-network` | `/graph/domain-terms` |
| `term-network-related`, `term-network-structured` | the same with `?edges=related`, `?edges=structured` |
| `metamodel-graph.json` | `/metamodel` |
| `page-<ID>.mmd`, `page-<ID>-ego.json` | Detail page of one page: its diagram (hierarchy, whitebox, sequence, deployment) and its term network |

A file exists only when the fixture has pages for that diagram.
`goal-matrix.json` is not a diagram of its own: the dashboard renders the
goal coverage matrix as an HTML table, so the script reads it into
`columns` (`id`, `status`, `enabler`, `no_goal`) and `rows` per goal id
(`status`, `gap`, `gap_accepted`, `serves`, `served_by`).

The Go dashboard has no backlog view. The backlog is not exported.
