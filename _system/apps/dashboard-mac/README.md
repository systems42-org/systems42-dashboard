# Systems42 Dashboard, native Mac app

A SwiftUI app for macOS 14 or newer that reads a Systems42 derivative. It lives
next to the Python and Go dashboards in `_system/apps/dashboard/` and shares no
code with them. The Go code is the reference for behaviour.

| Target | Content |
|---|---|
| `Systems42Kit` | Reading the wiki. Foundation, Yams and swift-markdown only. |
| `Systems42UI` | SwiftUI views, depends on the Kit. |
| `Systems42Dashboard` | The executable. |
| `Systems42TestSupport` | `Fixture.url(_:)`, finds the test fixtures. |

## Build, run, test

Run all commands from the repository root. You need Xcode 16 or newer.

    swift build --package-path _system/apps/dashboard-mac
    swift test --package-path _system/apps/dashboard-mac
    swift run --package-path _system/apps/dashboard-mac Systems42Dashboard

`scripts/build-app.sh` builds a release binary and wraps it in
`build/Systems42 Dashboard Native.app` (bundle id `org.systems42.dashboard.native`).
The version comes from `_system/apps/dashboard/VERSION`. The app is not signed.

Yams and swift-markdown are pinned to exact versions in `Package.swift`, and
`Package.resolved` is committed.

## Diagrams

Graph diagrams (context, building blocks, deployment, data model, goal tree, term network, metamodel
graph, Mermaid blocks in pages) are drawn by the libraries the web dashboard ships, in a web view that
loads nothing from the network. The page and the libraries are in `Sources/Systems42UI/Resources/diagram/`.
`scripts/sync-diagram-assets.sh` copies the libraries from `_system/apps/dashboard/static/` and pins their
checksums in `CHECKSUMS`. `scripts/sync-diagram-assets.sh --check` compares the copies with the dashboard.
`Systems42Dashboard --check-diagram-assets` prints whether the files are found, and exits 0 or 1.
`build-app.sh` copies the resource bundle to `Contents/Resources/` before it signs the app.

## Fixtures

Tests read only `Tests/Fixtures/` and `Tests/Golden/`, never the live `wiki/`.
Each fixture is a small Systems42 derivative: `wiki/`, `raw/sources/`,
`_system/wiki.yaml`, `_system/metamodel/`, `_system/anchors/`.

| Fixture | Wiki pages from `_system/apps/dashboard/tests/fixtures/` |
|---|---|
| `basic` | `wiki/` |
| `search` | `search-wiki/` |
| `arc42` | `arc42/wiki/` |
| `arc42-views` | `arc42-views/wiki/` |
| `domain-model` | `domain-model/` |
| `hostile` | written by hand, see its `README.md` |
| `tailored` | `basic` with a renamed and an added section, see its `README.md` |

The fixtures are frozen copies and are committed. `hostile` holds broken pages, and
the script refreshes only its `_system/`. It leaves `tailored` alone. Refresh them on purpose:

    _system/apps/dashboard-mac/scripts/sync-fixtures.sh

Commit the sources first. The script refuses to run on uncommitted changes
there, and writes the last commit that changed them to `Tests/Fixtures/SOURCE`.
Running it twice leaves `git status` unchanged. CI never runs it. After a
refresh, update the counts in `FixtureTests` if they changed.

## Search

`Sources/Systems42Kit/Search/` ports the dashboard's search: `SearchIndex` builds what the Go
dashboard serves as `/search.json` (`internal/search/search.go`), and `search(_:in:filter:withPassages:)`
ranks it like `static/search-rank.js`. Each Swift function names the JavaScript function it ports, so
a change in the JavaScript can be followed. Tests compare the index and the ranking with the
golden data, see `Tests/Golden/README.md`. Running the tests needs neither Go nor Node. Regenerating
the golden data (`scripts/export-golden.sh`) needs both, and Python 3.

## Projections

`Sources/Systems42Kit/Projections/` ports the dashboard's projections: views computed from page fields and
never stored. `Projections(store:metamodel:agreedOnly:)` is a value you can build off the main actor. It
answers the requirement hierarchy, story map, goal coverage matrix and backlog, the Mermaid text of the
diagrams (`mermaid(_:)`) and the Cytoscape data of the term network and the metamodel (`graph(_:)`). The Go
code is the reference (`internal/project/`, `internal/web/projections.go`, `internal/web/metamodel.go`), and
each Swift function names the function it ports. The names `mermaid` and `graph` take are the file names of
the golden data in `Tests/Golden/<fixture>/diagrams/`. A test walks those files and compares every one.

The Go code names types, fields and values of the metamodel. Each projection file keeps them in one
`enum` at its top, with the Go place they come from, so the debt to the metamodel stays visible (CON-006).
Folders and id prefixes come from the metamodel. A projection is offered only when the metamodel has
its projection page (`Projections.available`), and a test compares the constants with the `reads:` of
that page. Text of a page that enters a Mermaid text goes through `Common.label` and `NodeIDs`, so an id
or a title cannot change the shape of a diagram. `mermaid(_:links:)` writes clicks as `.page` (the
reference the app reads) or `.dashboard` (the routes of the Go dashboard, which the golden data holds).

## CI

`.github/workflows/mac.yml` runs `swift build` and `swift test` on a macOS runner.
Its `paths` filter is the only trigger: a change under `wiki/` starts no job.
