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

The fixtures are frozen copies and are committed. Refresh them on purpose:

    _system/apps/dashboard-mac/scripts/sync-fixtures.sh

Commit the sources first. The script refuses to run on uncommitted changes
there, and writes the last commit that changed them to `Tests/Fixtures/SOURCE`.
Running it twice leaves `git status` unchanged. CI never runs it. After a
refresh, update the counts in `FixtureTests` if they changed.

## CI

`.github/workflows/mac.yml` runs `swift build` and `swift test` on a macOS runner.
Its `paths` filter is the only trigger: a change under `wiki/` starts no job.
