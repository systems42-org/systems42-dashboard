---
id: CC-001
type: crosscutting-concept
title: Tests of the Python dashboard are plain scripts
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-039-solution-strategy-of-the-dashboard]]", "[[SRC-040-grilling-session-on-the-solution-strategy]]"]
related: ["[[SOL-001-systems42-dashboard]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]"]
tags: [crosscutting-concept]
category: development
applies-to: []
drivers: []
decisions: []
state: current
superseded-by:
---

# Tests of the Python dashboard are plain scripts

> follows [[arc42]] (section 8)

## Concept

- Each test of the Python dashboard is a Python script that runs on its own, without a test framework.
- One command, `./dashboard.sh test`, runs all of them in Docker. A developer runs it on their machine, and it runs on every pull request.
- The concept applies to the Python dashboard only. Another implementation brings its own tests.
