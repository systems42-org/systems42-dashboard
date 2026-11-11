---
id: FR-014
type: functional-requirement
title: Reach the main content from the header
status: draft
created: 2026-11-11
updated: 2026-11-11
sources: ["[[SRC-010-header-and-footer-on-every-page]]", "[[SRC-011-grilling-session-on-header-and-footer]]"]
related: ["[[STK-015-newcomers]]"]
tags: ["functional-requirement", "page-frame"]
stereotype: story
parent: ["[[FR-013-header-and-footer-on-every-page]]"]
priority: Must
release: unscheduled
lane: backbone
order: 14
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Reach the main content from the header

## Story

As a [[STK-015-newcomers]] **newcomer** I want **to reach the main content from the header of every page**, so that **I get there in one click, wherever I am**.

> follows [[user-story-format]]

**Acceptance criteria.**

- **Given** any page **when** it is shown **then** the header has five entries in this order: Requirements, Architecture, Glossary, Decisions, Issues.
- **Given** a page that belongs to one of the five entries **when** it is shown **then** that entry is marked as current.
- **Given** the page of a goal **when** it is shown **then** Requirements is marked, because goals belong to the Requirements area.
- **Given** an area or section that is hidden in Configure **when** any page is shown **then** its entry is missing from the header.

**Scope.** in: the five entries · out: Commons. It has no entry, by choice (Q3). The reader reaches Stakeholders, Quality, Constraints and Scope & Context from the home page or by search.

## Hierarchy

- **Parent:** [[FR-013-header-and-footer-on-every-page]]
- **Children:** none.

> [!note] Open points
> None.

## History

> Until 2026-11-11 the header held Goals, Stakeholders, Functional Reqs, Quality and Issues. Changed in the conversation behind [[SRC-010-header-and-footer-on-every-page]]. Decisions and the missing Commons entry were confirmed by Gernot Starke ([[SRC-011-grilling-session-on-header-and-footer]], Q3).
