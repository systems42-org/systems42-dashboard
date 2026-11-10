---
id: DR-001
type: decision-record
title: Write all documentation in brief, plain English
status: accepted
created: 2026-11-10
updated: 2026-11-10
sources: []
related: []
tags: [decision-record]
aliases: []
kind: business
decided: 2026-11-10
decision-makers: [Gernot Starke]
consulted: []
informed: []
drivers: []
amends: []
superseded-by: []
---

# Write all documentation in brief, plain English

> follows [[MADR]]

## Context and Problem Statement

This wiki documents the requirements of the Systems42 dashboard. Its method files
came from the iSAQB atrium wiki, which writes German titles and body text with
English IDs and frontmatter. The dashboard's interface, code and method files are
English. Every page here gets reviewed by a human, so length costs review time.

Two questions: which language, and how to write.

## Considered Options

1. English throughout, written to the binding guide `_system/writing-style.md`
2. German content with English IDs and frontmatter, as in atrium
3. English throughout, with no binding style guide

## Decision Outcome

Chosen option: **1**, because readers then meet one language everywhere, from the
dashboard's interface to its code to this wiki. The guide keeps pages short enough
to review completely, and it rules out inflated wording, filler and recaps.

The guide covers wiki pages, docs, decision records, changelog and log entries,
commit messages and dashboard UI text. `AGENTS.md` points every writer to it.

### Consequences

- Good: no translation between the interface, the code and the requirements.
- Good: a reviewer can read a whole page and accept or reject each statement.
- Bad: German-speaking stakeholders read in their second language.
- Bad: older text meets the guide only when someone changes it, because the guide
  forbids rewriting untouched text.
- Bad: `make sync` from atrium overwrites `AGENTS.md` with atrium's version. That
  brings back the German rule and drops the pointer to the guide. Check
  `AGENTS.md` after every sync.

### Confirmation

Reviewers check new and changed text against the guide's final check. Nothing
checks it automatically.
