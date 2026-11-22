---
id: BB-002
type: building-block
title: uv CLI and package wrapper
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-044-building-blocks-of-the-systems42-dashboard]]", "[[SRC-045-grilling-session-on-context-and-building-blocks]]"]
related: ["[[SOL-002-three-ways-to-run-the-dashboard]]", "[[SOL-005-local-and-offline-execution]]"]
tags: [building-block]
parent: "[[CTX-001-systems42-dashboard-context]]"
drivers: ["[[FR-054-a-start-without-a-container-engine]]", "[[FR-042-start-a-pinned-release-with-one-command]]", "[[FR-050-stop-the-dashboard-when-nobody-is-watching]]", "[[QR-002-runs-alike-on-linux-and-macos]]", "[[QR-004-the-wikis-content-stays-on-the-machine]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]"]
decisions: ["[[DR-004-releases-are-container-images-pinned-per-wiki]]", "[[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]"]
uses: ["[[BB-001-python-dashboard]]"]
location: "_system/apps/dashboard/cli.py, _system/apps/dashboard/pyproject.toml"
state: current
superseded-by:
---

# uv CLI and package wrapper

> follows [[arc42]] (section 5, black box)

## Purpose / Responsibility

Packages [[BB-001-python-dashboard]] as a standard Python wheel (`systems42-dashboard`) attached to each GitHub release and exposes a `systems42-dashboard` CLI entry point. On machines where no container engine runs, `uv` downloads Python and the pinned release wheel on first start and runs the same Flask and Gunicorn server in the foreground ([[FR-054-a-start-without-a-container-engine]], [[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]).

## Interfaces

- **Provides:** The `systems42-dashboard [WIKI] | --version` command inside the release wheel, started in the foreground by [[BB-005-wiki-launcher-and-make-facade]] (`./dashboard.sh uv`) or directly via `uv tool run`.
- **Needs:** [[BB-001-python-dashboard]] modules, templates, static assets, brands and `requirements.txt` (bundled verbatim into the wheel via `pyproject.toml`), plus `uv` on the host.

## Quality / Performance

Starts offline from uv's cache after the first fetch of a release ([[QR-004-the-wikis-content-stays-on-the-machine]]) and stops on Ctrl+C or when the last browser tab closes ([[FR-050-stop-the-dashboard-when-nobody-is-watching]]). Automated tests verify that the wheel includes the exact same application files as the container image.
