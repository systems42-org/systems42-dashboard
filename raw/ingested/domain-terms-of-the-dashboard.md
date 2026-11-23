# Domain terms of the dashboard

Raised by Gernot Starke on 2026-11-22. Not yet captured into `wiki/`. Some terms repeat what the Systems42 method wiki (meta) defines. That is accepted here.

Obsidian has its own source: `raw/domain-term-obsidian.md`.

## The dashboard's own language

**Dashboard.** The read-only program that shows a Systems42 wiki in a browser. It comes in three forms: a Docker image, a uv start and an app for macOS.

**Systems42 wiki.** A repository that holds requirements and architecture as typed Markdown pages under `wiki/`, with sources under `raw/` and the method files under `_system/`.

**Systems42 derivative.** A repository created from Systems42 that carries its metamodel. The dashboard shows derivatives only.

**Projection.** A list, matrix or diagram that the dashboard computes from the pages each time it is asked. A projection is never stored.

**Area.** One of the three groups of sections: Requirements, Architecture, Commons.

**Section.** One chapter of req42 or arc42 as the metamodel declares it, for example R3 or A2. A section holds the pages of one or more wiki folders.

**Release.** A numbered version of the dashboard, published as Docker image, wheel and app.

**Pinned release.** The release a wiki names in `dashboard_version:` in `_system/wiki.yaml`. Everybody who starts the dashboard for that wiki gets this release.

**Brand.** Name, logo, colours and intro of a dashboard, set by configuration.

**Session.** The time during which several people look at the same running dashboard, for example in a workshop.

**Keyholder.** The one person in a session who may change the View and disconnect the others.

**View.** The choice of areas and sections that a session shows. It lasts until the dashboard stops.

**Reference implementation.** The Python dashboard. Every feature is built there first.

**Parity.** The Go dashboard shows the same pages for the same wiki as the Python dashboard of the same release.

## Formats and method

**Markdown.** The plain-text format of every wiki page. Homepage: <https://commonmark.org>

**Frontmatter.** The YAML block at the top of a page that holds its fields, such as `id`, `type` and `status`.

**Wikilink.** A link in double square brackets that names another page by its filename. The syntax comes from Obsidian.

**Metamodel.** The description of the page types, their fields, relations, sections and projections, in `_system/metamodel/`. Systems42 defines it. The dashboard reads it.

**Systems42.** The method and starter kit for requirements and architecture wikis that an LLM agent maintains. Homepage: <https://systems42.org>

**req42.** The framework for requirements whose sections form the Requirements area. Homepage: <https://req42.de>

**arc42.** The template for architecture documentation whose sections form the Architecture area. Homepage: <https://arc42.org>

**LLM wiki.** The pattern behind a Systems42 wiki: humans collect sources, an LLM agent writes and maintains the pages. Andrej Karpathy described it. Homepage: <https://karpathy.ai/>

**Mermaid.** The text language in which the dashboard writes its diagrams. The browser draws them. Homepage: <https://mermaid.js.org>

## Technology

**Docker.** The container engine that runs the dashboard's image. It is the primary and the only supported container engine. Homepage: <https://www.docker.com>

**Podman.** Another container engine. The dashboard does not support it. Homepage: <https://podman.io>

**uv.** A program that fetches Python and a release of the dashboard and starts it, for machines without a container engine. Homepage: <https://docs.astral.sh/uv/>

**Flask.** The Python web framework the Python dashboard is built on. Homepage: <https://flask.palletsprojects.com>
