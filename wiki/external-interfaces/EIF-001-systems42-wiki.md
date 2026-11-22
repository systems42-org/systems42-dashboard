---
id: EIF-001
type: external-interface
title: Systems42 wiki
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-043-context-of-the-systems42-dashboard]]", "[[SRC-045-grilling-session-on-context-and-building-blocks]]"]
related: ["[[CTX-001-systems42-dashboard-context]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]", "[[CON-005-the-dashboard-works-on-systems42-derivatives-only]]", "[[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]]", "[[FR-043-the-dashboard-checks-the-metamodel-version]]", "[[FR-044-sections-come-from-the-repositorys-metamodel]]"]
tags: [external-interface]
partner: Local Systems42 derivative repository on the host filesystem
tier:
short_title: Systems42 wiki
flows:
  - { data: "Wiki pages (wiki/**/*.md)", direction: inbound, format: "Markdown with YAML frontmatter", trigger: "Dashboard startup and page requests", label: "wiki pages" }
  - { data: "Metamodel definitions (_system/metamodel/)", direction: inbound, format: "Markdown with YAML frontmatter", trigger: "Dashboard startup and reload", label: "metamodel" }
  - { data: "Wiki identity, brand and optional docs (_system/wiki.yaml, brand/, docs/)", direction: inbound, format: "YAML, CSS, Markdown", trigger: "Dashboard startup and page requests", label: "config & brand" }
---

# Systems42 wiki

**Purpose.** Supplies all domain content, metamodel definitions and project configuration that the dashboard renders. The dashboard has no database of its own and reads only from a valid Systems42 derivative ([[CON-005-the-dashboard-works-on-systems42-derivatives-only]]).

**Flows.** Every flow is strictly inbound and read-only ([[CON-002-dashboard-never-writes-to-the-wiki]]). At startup and on page loads, the dashboard reads the typed Markdown pages and YAML frontmatter under `wiki/`, the metamodel files under `_system/metamodel/` ([[FR-043-the-dashboard-checks-the-metamodel-version]], [[FR-044-sections-come-from-the-repositorys-metamodel]]), and project settings and branding from `_system/wiki.yaml`, optional `brand/` assets and optional `docs/` pages. The dependency runs one way: the dashboard depends on the wiki's metamodel and never modifies it ([[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]], [[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]]).

**Belongs to.** [[CTX-001-systems42-dashboard-context]]
