# Building blocks of the Systems42 dashboard

Stated by Gernot Starke on 2026-11-22. Level 1 building blocks of the dashboard repository.

## Level 1 building blocks

1. **Python dashboard** (`state: current`, `_system/apps/dashboard/`)
   Reference Flask web application served with Gunicorn inside a Docker container image (DR-004, CON-003). Reads the Systems42 wiki and its metamodel, projects all views and diagrams, and serves HTML and JSON. Every feature is built here first and parity checks test against it (CON-007). Uses: Systems42 wiki.

2. **uv CLI and package wrapper** (`state: current`, `_system/apps/dashboard/cli.py`, `_system/apps/dashboard/pyproject.toml`)
   Packages the Python dashboard as a standard wheel (`systems42-dashboard`) with a foreground CLI entry point so `uv` fetches Python and runs the same Flask and Gunicorn server without a container engine (FR-054, DR-007). Uses: Python dashboard.

3. **Go dashboard** (`state: current`, `_system/apps/dashboard/cmd/systems42-dashboard/`, `_system/apps/dashboard/internal/`, `_system/apps/dashboard/assets.go`)
   Second, standalone implementation in Go compiled to a single static binary with embedded templates, static assets and brands (DR-007, FR-055). Delivers route parity with the Python dashboard without Docker or Python. Ships as Linux and Windows CLI binaries and serves as the embedded engine inside the macOS app. Uses: Systems42 wiki.

4. **macOS native app** (`state: current`, `_system/apps/dashboard/macos/`)
   Native Swift and AppKit menu-bar host (`AppDelegate.swift`, packaged as `Systems42 Dashboard.app` and a universal `.dmg`) that lets users pick a wiki folder, remembers recent wikis, manages the embedded Go dashboard process and opens the default browser (FR-055, DR-007). Ad-hoc signed today (not yet Apple-notarized). Uses: Go dashboard.

5. **Wiki launcher and Make facade** (`state: current`, `dashboard.sh`, `Makefile`)
   CLI entry point shipped into every Systems42 wiki (`dashboard.sh` plus the user-facing `Makefile` targets `dev`, `uv`, `down`, `clean` and `help`). Reads `dashboard_version:` from `_system/wiki.yaml`, starts the pinned Docker image or `uv` wheel and stops or cleans the local runtime (FR-042, FR-054, FR-063). Repo-only development and release commands live in `dev.sh` and the repository-only `Makefile` targets (FR-063). Uses: Python dashboard, uv CLI and package wrapper, Systems42 wiki.

6. **Public website builder** (`state: current`, `site/`)
   Python build script (`site/build.py`), templates and Docker wrappers (`site/build.sh`, `site/serve.sh`) that build `dashboard.systems42.org` and export a static live demo from the Python dashboard (FR-056 to FR-062, SOL-001). Uses: Python dashboard, Systems42 wiki.
