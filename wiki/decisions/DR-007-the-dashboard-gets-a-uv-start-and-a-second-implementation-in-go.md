---
id: DR-007
type: decision-record
title: The dashboard gets a uv start and a second implementation in Go
status: draft
created: 2026-11-20
updated: 2026-11-20
sources: ["[[SRC-036-grilling-session-on-running-without-a-container-engine]]"]
related: ["[[DR-004-releases-are-container-images-pinned-per-wiki]]", "[[DR-005-the-dashboard-lives-in-its-own-repository]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[STK-010-operators]]", "[[STK-012-maintainers]]"]
tags: [decision-record]
aliases: []
kind: architecture
decided: 2026-11-20
decision-makers: [Gernot Starke]
consulted: [Claude]
informed: []
drivers: ["[[FR-054-a-start-without-a-container-engine]]", "[[FR-055-an-installable-dashboard-app]]", "[[GOAL-008-one-way-into-every-systems42-wiki]]"]
amends: ["[[DR-004-releases-are-container-images-pinned-per-wiki]]"]
superseded-by: []
---

# The dashboard gets a uv start and a second implementation in Go

> follows [[MADR]]

## Context and Problem Statement

Some people run their Systems42 wiki inside a virtual machine, where neither Docker nor Podman starts. A release is a container image and nothing else ([[DR-004-releases-are-container-images-pinned-per-wiki]]), so these people have no dashboard.

How does the dashboard reach a machine without a container engine?

## Decision Drivers

- The dashboard must start where no container engine runs ([[FR-054-a-start-without-a-container-engine]]).
- People who do not work in a terminal need an app they can install ([[FR-055-an-installable-dashboard-app]]).
- Every wiki still uses the same released dashboard ([[GOAL-008-one-way-into-every-systems42-wiki]]).

## Considered Options

1. **A start with uv only.** Every release carries a Python package, and uv runs it. One codebase. It needs uv and a terminal.
2. **A start with uv, and the Python dashboard packaged as an app.** The app bundles Python and the existing code. One codebase and one set of tests, an app of 30 to 50 MB.
3. **A start with uv, and a Go shell around the Python dashboard.** A Go app starts a bundled Python server. One codebase for the pages, two runtimes in one app.
4. **A start with uv, and a second implementation in Go.** A small app without a runtime to bundle. Two codebases that must show the same pages.

## Decision Outcome

Chosen option: **4**. Gernot Starke wants the Go implementation as a second version of the dashboard and accepts that it is more work. Claude recommended option 2, because it keeps one codebase.

The decision has two parts:

- **uv.** Every release carries a Python package (a wheel) on its GitHub release, next to the container image. `./dashboard.sh uv` runs the package of the release the wiki names. This amends [[DR-004-releases-are-container-images-pinned-per-wiki]], which set a Python package aside because it needs Python on every machine: uv fetches Python itself.
- **Go.** A second implementation of the dashboard in Go is delivered as an installable app, for macOS first. It lives in the dashboard's repository ([[DR-005-the-dashboard-lives-in-its-own-repository]]) and shares the release number of the Python dashboard.

### Consequences

- Good: the dashboard runs without a container engine, in two ways.
- Good: the container start stays as it is.
- Bad: every page and every later feature is built and tested twice, in Python and in Go.
- Bad: the two implementations can drift apart. A test that compares their pages for the same wiki has to hold them together.
- Bad: one installed app serves every wiki on the machine, so a wiki cannot hold the app to its release as it holds the image.
- Bad: an app for macOS must be signed and notarised, which needs an Apple developer account.

## More Information

The plan for the Go implementation is [issue #80](https://github.com/systems42-org/systems42-dashboard/issues/80).
