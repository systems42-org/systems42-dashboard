---
id: FR-006
type: functional-requirement
title: Tags and fields are searched
status: draft
created: 2026-11-11
updated: 2026-11-11
sources: ["[[SRC-005-search-the-wiki]]", "[[SRC-006-grilling-session-on-search]]"]
related: ["[[FR-009-more-filters-on-the-full-results-page]]"]
tags: ["functional-requirement", "search"]
stereotype: feature
parent: ["[[FR-001-search-the-wiki]]"]
priority: Should
release: unscheduled
lane: backbone
order: 6
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Tags and fields are searched

## Story

As a [[STK-001-product-owners]] **product owner** I want **search to find pages by their tags and by values such as `Must` or `security`**, so that **I find pages by what they are labelled with, not only by their wording**.

**PROBLEM / GOAL**

Readers look for pages by their labels, such as a tag or a priority, not only by their wording.

- Searched as plain words: `tags`, `status`, `stereotype`, `priority`, `kind`, `state`, `category` and `attribute` (the quality attribute).
- Not searched as text: link fields such as `parent:`, `sources:`, `related:` and `drivers:`. Their raw values are file names and only add noise. [[FR-008-related-pages-group]] uses the links instead.
- Not searched at all: dates, and dashboard display fields such as `short_title` and `tile_claim`.
- A hit in a field ranks below a title hit and above a body-text hit, because a tag is a deliberate label.

**Success metric(s).** On a fixed test wiki:

- `Must` finds the pages with `priority: Must`.
- A tag hit ranks above a page that has the word only in its body.

**Scope.** in: the fields listed above, on every page type · out: filter syntax such as `priority:Must` (see [[FR-009-more-filters-on-the-full-results-page]]).

## Hierarchy

- **Parent:** [[FR-001-search-the-wiki]]
- **Children:** none.

> [!note] Open points
> None.

## History

> The gap "tags and frontmatter fields are not searched" came from [[SRC-005-search-the-wiki]]. The split was set in Q4 of [[SRC-006-grilling-session-on-search]].
