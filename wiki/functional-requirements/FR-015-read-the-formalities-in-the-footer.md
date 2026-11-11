---
id: FR-015
type: functional-requirement
title: Read the formalities in the footer
status: draft
created: 2026-11-11
updated: 2026-11-11
sources: ["[[SRC-010-header-and-footer-on-every-page]]", "[[SRC-011-grilling-session-on-header-and-footer]]"]
related: ["[[STK-013-people-learning-or-presenting-systems42]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]"]
tags: ["functional-requirement", "page-frame"]
stereotype: story
parent: ["[[FR-013-header-and-footer-on-every-page]]"]
priority: Should
release: unscheduled
lane: backbone
order: 15
goal: ["[[GOAL-006-source-and-status-on-every-statement]]", "[[GOAL-002-show-what-systems42-can-do]]"]
---

# Read the formalities in the footer

## Story

As a [[STK-013-people-learning-or-presenting-systems42]] **person learning or presenting Systems42** I want **the footer of every page to say what this dashboard is, how current its data is and what it is built on**, so that **I can answer those questions without leaving the page**.

> follows [[user-story-format]]

**Acceptance criteria.**

- **Given** any page **when** it is shown **then** the footer reads "Read-only dashboard for Systems42 LLM wiki", and "LLM wiki" links to the help section that explains it. The wiki is read-only because of [[CON-002-dashboard-never-writes-to-the-wiki]].
- **Given** any page **when** it is shown **then** the footer shows when the data was last refreshed, as date and time without a time zone, for example "2026-11-11 10:02:08h". This is the time the page was loaded.
- **Given** a running session **when** a page is shown **then** the footer shows how many clients are connected.
- **Given** any page **when** it is shown **then** the footer links to the Metamodel page and to Help.
- **Given** any page **when** it is shown **then** the footer shows the two-colour Python logo and the word "Python" as the technology credit.
- **Given** any page **when** it is shown **then** the footer has no link to wiki content and no link that the header has.

## Hierarchy

- **Parent:** [[FR-013-header-and-footer-on-every-page]]
- **Children:** none.

> [!note] Open points
> None.

## History

> The footer line replaces "Live view · (system name) wiki dashboard", the note "wiki read-only" and the credit "Karpathy LLM-wiki". The logo replaces the text "Python/Flask" ([[SRC-010-header-and-footer-on-every-page]]). Requirements may name a technology here, because this project's subject is technology ([[SRC-011-grilling-session-on-header-and-footer]], Q1).
