# Solution strategy of the dashboard

Stated by Gernot Starke on 2026-11-21 and 2026-11-22, worded by Claude.

- **Part A, strategy.** Sections 1 to 3 are Gernot Starke's statements. Sections 4 to 8 were proposed by Claude from the wiki and the code. Gernot Starke confirmed them as strategy on 2026-11-22.
- **Part B, decision proposals.** Lower-level design, proposed by Claude. Gernot Starke sorted these out of the strategy. He has not decided on any of them.

## Part A: Strategy

### 1. Three ways to run the dashboard

The dashboard is offered in three forms. Each one answers a different environment.

1. **Python with Flask, in Docker.** The first and main implementation. A person with Docker starts it with one command and installs nothing else. Python and Flask keep the code small and easy to change.
2. **The same Python code, started with uv.** For environments where neither Docker nor Podman can run, for example a virtual machine. uv fetches Python and the libraries itself.
3. **A second implementation in Go.** An installable app that does not depend on the operating system's tooling: no container engine, no Python. macOS first, other systems later.

The Docker and uv starts run the same code. The Go app is a second codebase and has to show the same pages for the same wiki.

### 2. The dashboard stays separate from Systems42

The dashboard has its own repository. The Systems42 metamodel and templates stay in theirs (`systems42-org/meta`). Reasons:

1. **Separation of concerns.** Systems42 defines the method: types, fields, relations, templates, workflows. The dashboard only shows a wiki built with them. Each side changes and releases at its own pace.
2. **The dashboard is a case study.** It is a system specified with Systems42 like any other, with its requirements, decisions and code in one repository. That shows the method at work on a real product and tests it at the same time.
3. **The method does not need the dashboard.** A Systems42 wiki works in Obsidian, in an editor or for an AI agent. The dependency runs one way: the dashboard depends on the metamodel, never the reverse.

### 3. A public website on GitHub Pages

The dashboard has a public website. A build script of its own (`site/build.py`, Python) makes it: it renders the pages from templates and exports the demo from the dashboard's own code. GitHub Actions runs that build and publishes the result on GitHub Pages. No server to run and no hosting to pay.

The site uses no site generator, because the demo can only come from the dashboard itself. That build needs Python anyway, and the few other pages use the same template language as the dashboard. Gernot Starke decided on 2026-11-22 to keep this build.

### 4. Read-only, and the wiki is the only data store

The dashboard never writes to the wiki and has no database. The Markdown files are the single source of truth.

### 5. Everything shown is a projection

Lists, matrices and diagrams are computed from the pages and their typed links. Nothing drawn is stored, so nothing drawn can go stale.

### 6. The metamodel drives the dashboard

Types, fields and allowed values are read from `_system/metamodel/`, not written into the code. The dashboard checks the metamodel version of the wiki it shows.

### 7. Pages are rendered on the server

HTML comes from templates, with little JavaScript. Static diagrams are Mermaid. Only the interactive networks are laid out in the browser.

### 8. Everything runs locally and offline

No account, no cloud service, no tracking. Script libraries are shipped with the dashboard, not loaded from a network. A wiki's content never leaves the machine.

## Part B: Decision proposals

Each of these already shapes the code. None is decided here.

1. **A release is pinned per wiki.** Each wiki names the release it runs. Image, Python package and Go app share one release number.
2. **No access control, one process, session state in memory.** The dashboard is a proof of concept for a trusted network, such as a workshop room. It is not built for the open internet.
3. **Python is the reference, Go follows.** A new feature is built in Python first. A parity test compares the pages of both implementations for the same wiki.
4. **Tests are plain scripts that run in Docker.** No test framework. The same command runs them on a developer machine and in CI, on every pull request.
5. **Every diagram has a text equivalent.** Each node is also a link in a list, so the dashboard works on a phone and with a screen reader.
6. **Tailoring by configuration.** A project sets its name, brand and views in configuration files, without changing the code.

## Open questions

- **Three forms for how long.** Is the Go app meant to replace the Python dashboard one day, or do both stay?
- **Windows and Linux.** Which of the three forms is the answer for Windows users?
