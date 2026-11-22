# Go Dashboard: Requirements Summary

The Go dashboard is a second implementation of the Systems42 dashboard, built to run without Docker, uv, Python or a terminal and delivered as an installable desktop app (macOS first, Windows later). It runs next to the Python reference implementation and serves the same pages for the same wiki.

Traceability: [FR-055](../wiki/functional-requirements/FR-055-an-installable-dashboard-app.md), [DR-007](../wiki/decisions/DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go.md), [FR-054](../wiki/functional-requirements/FR-054-a-start-without-a-container-engine.md), [GOAL-008](../wiki/goals/GOAL-008-one-way-into-every-systems42-wiki.md), and [issue #80](https://github.com/systems42-org/systems42-dashboard/issues/80).

## Why we built it

1. **Virtual machines without containers.** Many teams run their Systems42 wiki inside a virtual machine where neither Docker nor Podman starts (`DR-007`, `SRC-036`). Container-only releases (`DR-004`) left those users without a dashboard.
2. **Users without a terminal.** `./dashboard.sh uv` (`FR-054`) removed the Docker dependency, but still requires uv and a shell. Non-technical readers and workshop facilitators need an app they install once and open by clicking or dropping a wiki folder (`FR-055`).
3. **Small, self-contained binary.** In `DR-007`, four options were weighed: uv only (Option 1), bundling Python into a 30 to 50 MB app (Option 2), a Go wrapper starting a bundled Python runtime (Option 3), and a second implementation in Go (Option 4). Gernot Starke chose Option 4 so the desktop app carries no bundled scripting runtime and starts immediately, accepting the cost of keeping two codebases aligned via automated parity tests.

## Core requirements

| Area | Requirement | What the Go app guarantees |
|------|-------------|----------------------------|
| **Docker independence** | `FR-054`, `FR-055`, `DR-007` | Single static Go binary (`CGO_ENABLED=0`) with embedded `static/`, `templates/`, `brands/`, `help.md` and `VERSION`. Needs no container engine, no Python and no uv. |
| **OS independence** | `QR-002`, `FR-055`, `CON-003` | The server (`cmd/systems42-dashboard/`, `internal/`) is pure Go and cross-compiles for macOS (`arm64`, `amd64`), Linux (`arm64`, `amd64`) and Windows (`amd64`, `arm64`). macOS ships first. Windows support is deferred (`CON-003`). |
| **Distributable desktop app** | `FR-055`, issue `#80` | Packaged as universal `Systems42 Dashboard.app` and `.dmg` installer (plus a Homebrew cask), with a macOS menu-bar status item, native folder picker, Finder drag-and-drop, recent wikis under `~/Library/Application Support/Systems42 Dashboard/recent.json`, and one free TCP port per running wiki. |
| **One app for every wiki** | `GOAL-008`, `FR-055`, `FR-043` | Installed once and opens any Systems42 wiki. When a wiki names another `dashboard_version:` in `_system/wiki.yaml`, the app shows the footer notice and displays the wiki anyway without downloading another release. It also runs the metamodel version check (`FR-043`). |
| **Read-only wiki** | `CON-002` | Never writes any file inside `wiki/`, `raw/` or the wiki repository. Recent wiki paths live in user application support, and session view settings (`FR-046`) stay in memory only. |
| **Systems42 derivatives only** | `CON-005` | Runs the same preflight (`wiki/`, `raw/`, `_system/wiki.yaml`, `_system/metamodel/`, `_system/anchors/`) via `--check` and refuses any other folder by naming what is missing. |
| **Workshop sessions and lifecycle** | `FR-046`, `FR-050`, `QR-001`, `QR-003` | Opens in the default browser so phones can join over LAN via the inline QR code (`/join`), tracks connected clients (`/who`) and Keyholder view hiding (`/settings`), and shuts down automatically when the last browser tab closes (`FR-050`). |
| **Parity and security boundary** | `DR-007`, issue `#80` | Renders the shared 40 Jinja2 templates directly via `gonja/v2` and matches Python's HTML allow-list sanitiser and CSP headers. Verified on every PR by `tests/test_parity.py` (644 routes across 7 wikis, 0 unported routes), `tests/test_search_examples.py` (42 search queries against both Python and Go), and Go hostile-vault tests (`internal/web/hostile_vault_test.go`). |

## Three ways to run the dashboard

| Method | Needs on the machine | Pins wiki's `dashboard_version:` | Target audience |
|--------|----------------------|----------------------------------|-----------------|
| **Docker** (`./dashboard.sh` / `make dev`) | Docker | Yes (pulls matching GHCR image) | Standard developer setup (`CON-003`) |
| **uv** (`./dashboard.sh uv` / `make uv`) | `uv` | Yes (runs matching release wheel) | Linux/macOS machines and VMs without Docker (`FR-054`) |
| **Go desktop app** (`Systems42 Dashboard.app` or `systems42-dashboard`) | None (macOS 14+ universal `.dmg` or static Go binary) | No (shows mismatch notice, still opens wiki) | macOS users and VMs without Docker, uv, Python or a terminal (`FR-055`) |

## Current state and remaining items

- **Complete (Phases 0 to 8):** full Go server with 100% route parity (644/644 checks across 7 wikis, 0 unported), Go hostile-vault security suite, CLI `--check` / `--port 0` / `--ready-json` / `--open`, universal macOS `.app` and `.dmg` builder (`make app-bundle`), Homebrew cask definition, GitHub Actions release pipeline (`.github/workflows/release.yml`), PR parity checklist, and user documentation.
- **Pending operational setup:** configure `APPLE_SIGN_P12`, `APPLE_SIGN_PASSWORD`, `APPLE_SIGN_IDENTITY`, `APPLE_NOTARY_KEY`, `APPLE_NOTARY_KEY_ID` and `APPLE_NOTARY_ISSUER_ID` repository secrets so GitHub releases sign with Developer ID and notarise the `.dmg` automatically (until then, builds ad-hoc sign cleanly).
- **Deferred (out of scope per `CON-003`):** Windows desktop tray shell, Windows installer, Authenticode signing and a Windows CI parity runner. The Go server itself already builds cleanly with `GOOS=windows CGO_ENABLED=0`.
