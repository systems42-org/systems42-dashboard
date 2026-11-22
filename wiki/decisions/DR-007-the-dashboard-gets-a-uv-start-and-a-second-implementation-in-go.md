---
id: DR-007
type: decision-record
title: The dashboard gets a uv start and implementations in Go and Swift
status: draft
created: 2026-11-20
updated: 2026-11-22
sources: ["[[SRC-036-grilling-session-on-running-without-a-container-engine]]", "[[SRC-049-grilling-session-on-the-mac-native-app]]"]
related: ["[[DR-004-releases-are-container-images-pinned-per-wiki]]", "[[DR-005-the-dashboard-lives-in-its-own-repository]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[STK-010-operators]]", "[[STK-012-maintainers]]", "[[CON-007-the-python-dashboard-is-the-reference-for-the-other-implementations]]", "[[FR-065-a-mac-native-dashboard-app]]"]
tags: [decision-record]
aliases: []
kind: architecture
decided: 2026-11-22
decision-makers: [Gernot Starke]
consulted: [Claude]
informed: []
drivers: ["[[FR-054-a-start-without-a-container-engine]]", "[[FR-055-an-installable-dashboard-app]]", "[[GOAL-008-one-way-into-every-systems42-wiki]]", "[[FR-065-a-mac-native-dashboard-app]]"]
amends: ["[[DR-004-releases-are-container-images-pinned-per-wiki]]"]
superseded-by: []
---

# The dashboard gets a uv start and implementations in Go and Swift

> follows [[MADR]]

## Context and Problem Statement

Some people run their Systems42 wiki inside a virtual machine, where neither Docker nor Podman starts. A release is a container image and nothing else ([[DR-004-releases-are-container-images-pinned-per-wiki]]), so these people have no dashboard.

How does the dashboard reach a machine without a container engine?

Two days later a second question followed. The Go app shows its pages in the browser and needs a reload after every change. People who write the wiki on a Mac want a window that follows the files and behaves like a Mac app ([[FR-065-a-mac-native-dashboard-app]]).

How does the dashboard become a Mac app of its own?

## Decision Drivers

- The dashboard must start where no container engine runs ([[FR-054-a-start-without-a-container-engine]]).
- People who do not work in a terminal need an app they can install ([[FR-055-an-installable-dashboard-app]]).
- Every wiki still uses the same released dashboard ([[GOAL-008-one-way-into-every-systems42-wiki]]).
- People who work on the wiki on a Mac see a saved change at once, in a Mac app ([[FR-065-a-mac-native-dashboard-app]]).

## Considered Options

For the machine without a container engine (2026-11-20):

1. **A start with uv only.** Every release carries a Python package, and uv runs it. One codebase. It needs uv and a terminal.
2. **A start with uv, and the Python dashboard packaged as an app.** The app bundles Python and the existing code. One codebase and one set of tests, an app of 30 to 50 MB.
3. **A start with uv, and a Go shell around the Python dashboard.** A Go app starts a bundled Python server. One codebase for the pages, two runtimes in one app.
4. **A start with uv, and a second implementation in Go.** A small app without a runtime to bundle. Two codebases that must show the same pages.

For the Mac app of its own (2026-11-22):

- **A. The Go app only.** No further codebase. Pages stay in the browser and change after a reload.
- **B. A window with a web view for the Go app.** The same pages in a window of the app. Little new code. Still a local server, and menus and windows around web pages.
- **C. A third implementation in Swift.** It reads the wiki folder directly, follows the files and draws its own windows. A third codebase.

## Decision Outcome

Chosen options: **4** and **C**. Gernot Starke wants the Go implementation as a second version of the dashboard and the Swift implementation as a third, and accepts that it is more work. For the first question Claude recommended option 2, because it keeps one codebase.

The decision has three parts:

- **uv.** Every release carries a Python package (a wheel) on its GitHub release, next to the container image. `./dashboard.sh uv` runs the package of the release the wiki names. This amends [[DR-004-releases-are-container-images-pinned-per-wiki]], which set a Python package aside because it needs Python on every machine: uv fetches Python itself.
- **Go.** A second implementation of the dashboard in Go is delivered as an installable app, for macOS first. It lives in the dashboard's repository ([[DR-005-the-dashboard-lives-in-its-own-repository]]) and shares the release number of the Python dashboard.
- **Swift.** A third implementation in Swift is a Mac-native app. It ships next to the Go app, lives in the same repository and shares the release number ([[SRC-049-grilling-session-on-the-mac-native-app]]).

The three implementations are equal products. For what a page shows, the Python dashboard is the reference ([[CON-007-the-python-dashboard-is-the-reference-for-the-other-implementations]]).

### Consequences

- Good: the dashboard runs without a container engine, in three ways.
- Good: the container start stays as it is.
- Good: on a Mac the wiki shows in a window that follows the files, without a server on the machine.
- Bad: every page and every later feature is built and tested three times, in Python, in Go and in Swift.
- Bad: the implementations can drift apart. A test that compares the pages of the Python and the Go dashboard for the same wiki has to hold these two together.
- Bad: the Swift app produces no HTML, so it is compared on data taken from the Go dashboard, not on pages. Differences in what a reader sees can pass this test.
- Bad: the Swift app has no shared session ([[FR-046-shared-session-in-a-workshop]]). A workshop still needs one of the other two.
- Bad: one installed app serves every wiki on the machine, so a wiki cannot hold the app to its release as it holds the image.
- Bad: an app for macOS must be signed and notarised, which needs an Apple developer account. This holds for both apps.

## More Information

The plan for the Go implementation is [issue #80](https://github.com/systems42-org/systems42-dashboard/issues/80). The plan for the Swift implementation is [issue #112](https://github.com/systems42-org/systems42-dashboard/issues/112).

The file keeps its first name, because code and documents outside the wiki link to it.
