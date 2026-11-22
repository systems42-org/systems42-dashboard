# Context of the Systems42 dashboard

Stated by Gernot Starke on 2026-11-22.

## System in scope

The Systems42 dashboard reads a local Systems42 requirements wiki and renders its pages, lists, matrices, diagrams, search results and method help in a browser. It runs locally and offline (QR-004), supports shared read-only workshop sessions on a trusted network (CON-001) and exports a static live demo for the public website (FR-056).

## Out of scope

- Editing, creating or deleting wiki files or raw sources (CON-002).
- Defining or changing the Systems42 metamodel (CON-004, CON-006).
- Serving non-Systems42 Markdown folders or general Obsidian vaults (CON-005).
- Authentication, access control or exposure on the public internet (CON-001).
- Cloud storage, accounts or external telemetry (QR-004).

## External neighbouring systems

The dashboard has one external neighbouring system:

- **Systems42 wiki** (inbound, read-only). A local Systems42 derivative repository on the host filesystem. The dashboard reads Markdown pages with YAML frontmatter under `wiki/`, metamodel definitions under `_system/metamodel/`, wiki identity and branding under `_system/wiki.yaml` and optional `brand/` and `docs/` folders. No data flows back to the wiki (CON-002).

Release registries (GitHub Releases, GHCR) and website hosting (GitHub Pages) are distribution and hosting infrastructure, not runtime neighbours of the dashboard.

## User groups

- **Readers.** Everyone who reads a wiki through the browser: Readers (STK-001), Workshop participants and facilitators (STK-008) and People learning or presenting Systems42 (STK-013).
- **Operators (STK-010).** Set up a project wiki and start, stop or clean up the dashboard.
- **Keyholder (STK-023).** Controls the visibility settings and can end a shared workshop session.
