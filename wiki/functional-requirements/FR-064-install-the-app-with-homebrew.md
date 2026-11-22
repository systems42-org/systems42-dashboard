---
id: FR-064
type: functional-requirement
title: Install the app with Homebrew
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-047-install-the-app-with-homebrew]]", "[[SRC-048-grilling-session-on-installing-with-homebrew]]"]
related: ["[[STK-010-operators]]", "[[FR-030-numbered-releases]]", "[[FR-059-downloads-on-the-website]]", "[[BB-004-macos-native-app]]"]
tags: ["functional-requirement", "product"]
notation: agile
level: story
parent: ["[[FR-055-an-installable-dashboard-app]]"]
priority: Could
release: unscheduled
lane: backbone
order: 64
goal: ["[[GOAL-008-one-way-into-every-systems42-wiki]]"]
---

# Install the app with Homebrew

## Story

> follows [[user-story-format]], [[INVEST]]

As a [[STK-010-operators|person who runs the dashboard]] on macOS I want **to install, update and remove the dashboard app with Homebrew**, so that **I manage it like my other programs and get new releases without a download by hand**.

**Acceptance criteria.** > follows [[acceptance-criteria]]

- **Given** a Mac with Homebrew **when** I run `brew install --cask systems42-org/tap/systems42-dashboard` **then** the app of the newest release is in Applications.
- **Given** an installed app and a newer release **when** I run `brew upgrade` **then** the app is the newest release.
- **Given** an installed app **when** I run `brew uninstall --cask systems42-dashboard` **then** the app is gone.
- **Given** a download that differs from the release **then** Homebrew refuses it, because the cask carries the checksum of the release.
- **Given** a new release ([[FR-030-numbered-releases]]) **then** the cask names it without a manual step.
- **Given** the install guide **then** it names these commands.

**Scope.** in: install, update and remove with Homebrew from a tap of the Systems42 organisation · out: opening the app without a security warning of macOS, Homebrew's own tap, Linux.

## Hierarchy

- **Parent:** [[FR-055-an-installable-dashboard-app]]
- **Children:** none.

> [!note] Open points
> - The app is ad-hoc signed and not notarised with Apple. Homebrew marks its downloads as a browser does, so macOS may refuse the first start after an install until the person allows it.
> - The tap is a repository `systems42-org/homebrew-tap`. It does not exist yet.
> - Built today: a cask file in the dashboard's repository that no tap offers, so nobody can install with Homebrew. It skips the checksum and names release 0.13.0.

## History

> Asked for by Gernot Starke on 2026-11-22 ([[SRC-047-install-the-app-with-homebrew]]). He decided that the requirement is met by installing, not by opening without a warning, set the priority Could and confirmed the tap `systems42-org/homebrew-tap` ([[SRC-048-grilling-session-on-installing-with-homebrew]]).
