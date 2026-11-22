---
id: DR-009
type: decision-record
title: Pages are rendered on the server from HTML templates
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-039-solution-strategy-of-the-dashboard]]", "[[SRC-046-grilling-session-on-modularizing-the-solution-strategy]]", "[[SRC-049-grilling-session-on-the-mac-native-app]]"]
related: ["[[DR-006-interactive-diagrams-are-projected-on-the-server-and-laid-out-in-the-browser]]", "[[BB-001-python-dashboard]]", "[[BB-003-go-dashboard]]", "[[BB-006-public-website-builder]]", "[[QR-004-the-wikis-content-stays-on-the-machine]]", "[[FR-065-a-mac-native-dashboard-app]]"]
tags: [decision-record]
aliases: []
kind: architecture
decided: 2026-11-22
decision-makers: [Gernot Starke]
consulted: [Claude]
informed: []
drivers: ["[[QR-001-usable-on-phone-and-tablet]]", "[[QR-003-works-in-every-current-browser]]", "[[FR-058-a-demo-to-try-without-installing]]", "[[CON-007-the-python-dashboard-is-the-reference-for-the-other-implementations]]"]
amends: []
superseded-by: []
---

# Pages are rendered on the server from HTML templates

> follows [[MADR]]

## Context and Problem Statement

The dashboard renders Markdown wiki pages, lists, matrices and diagrams for every current browser, including phones and tablets ([[QR-001-usable-on-phone-and-tablet]], [[QR-003-works-in-every-current-browser]]), and must also export cleanly to static HTML for the public demo ([[FR-058-a-demo-to-try-without-installing]]). Both a Python implementation and a Go implementation serve the same views ([[CON-007-the-python-dashboard-is-the-reference-for-the-other-implementations]]).

How should the dashboard assemble and deliver its web pages to the browser?

## Decision Drivers

- Pages must work across current desktop and mobile browsers without heavy client dependencies ([[QR-001-usable-on-phone-and-tablet]], [[QR-003-works-in-every-current-browser]]).
- Every diagram node must remain accessible as a plain HTML link beside the picture.
- Static HTML export for the public demo must work without running a headless browser ([[FR-058-a-demo-to-try-without-installing]]).
- Codebase and build setup should stay small and free of a frontend bundler.

## Considered Options

1. **Server-rendered HTML templates with minimal JavaScript.** The server renders complete HTML pages from templates, uses Mermaid for static diagrams and ships small vendored JavaScript only where interactivity is needed (search popup, session heartbeat and interactive graph layout per [[DR-006-interactive-diagrams-are-projected-on-the-server-and-laid-out-in-the-browser]]).
2. **Client-side single-page application (SPA).** The server exposes a JSON API and a JavaScript framework (such as React, Vue or Svelte) renders all views in the browser.

## Decision Outcome

Chosen option: **1, server-rendered HTML templates with minimal JavaScript**, because it avoids a JavaScript build pipeline, renders cleanly on phones and screen readers with text links beside every diagram, simplifies automated route-parity checks between [[BB-001-python-dashboard]] and [[BB-003-go-dashboard]], and allows [[BB-006-public-website-builder]] to export the live demo by saving HTTP responses directly.

### Consequences

- Good: zero frontend build tooling (no Node bundler required to run or build the dashboard).
- Good: Python and Go implementations share the same static CSS, vendored scripts and HTML structure, making HTML parity testing straightforward.
- Good: static demo export saves rendered HTML straight from route handlers.
- Bad: richer client-side interactions (such as drag-and-drop editing or complex stateful client views) require targeted JavaScript modules or a future shift to another UI architecture.
- Bad: template logic has to stay aligned between Jinja2 in Python and template rendering in Go.

### Confirmation

Route-parity tests (`tests/test_parity.py`) compare rendered HTML responses of [[BB-001-python-dashboard]] and [[BB-003-go-dashboard]], and `make site` exports all demo routes to static HTML without executing client-side JavaScript.

### Out of scope

The Mac-native app draws its pages itself and serves no HTML ([[FR-065-a-mac-native-dashboard-app]]). This decision covers the Python and the Go dashboard.

## More Information

Recorded as an architectural decision rather than a fixed solution-strategy pillar because upcoming implementations may choose a different UI rendering approach ([[SRC-046-grilling-session-on-modularizing-the-solution-strategy]]). Pairs with [[DR-006-interactive-diagrams-are-projected-on-the-server-and-laid-out-in-the-browser]] for interactive networks.
