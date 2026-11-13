# The dashboard as a product with releases

Raised by Gernot Starke on 2026-11-13. Written up by Claude for inspection. Not captured, nobody has agreed it yet.

**Requirement.** The dashboard is a product of its own, with numbered releases. Any requirements wiki uses a released version as it is, without copying or editing dashboard code. What makes it look like one project or brand is configuration.

**Serves.** GOAL-002 "Show what Systems42 can do", and a new goal (Gernot Starke, 2026-11-13):

> The dashboard is a reusable, consistent and efficient way into any Systems42 wiki.

GOAL-006 "Source and status on every statement" is more a goal of the Systems42 approach itself than of the dashboard.

**For.**
- People who set up a wiki: the Keyholder, facilitators, the Systems42 team.
- Workshop participants, who start it on their own laptop.
- Teams who adopt the Systems42 starter kit.

## Needs

### 1. Releases

- Every release has a version number and release notes taken from `CHANGELOG.md`.
- A wiki names the version it uses. It moves to a newer one only on purpose.
- A new release never changes a wiki that did not ask for it.
- The dashboard code lives in one place, this repository. Other wikis (isaqb-atrium, the starter kit, project wikis) hold no copy of it.

### 2. Runs on Windows, Linux and macOS

- Docker is required. Nothing else needs to be installed for the dashboard itself.
- One release behaves the same on all three systems.
- After the first start, it runs without network (CON-001).

### 3. Starting and stopping

- `make dev` starts the dashboard, `make down` stops it, `make clean` removes what can be rebuilt.
- The Makefile calls `dashboard.sh`. That is enough for Linux and macOS for now.
- A start script for Windows follows later.

### 4. Branding is configuration

- A wiki may have a brand folder. It holds the marks (dark and light theme), the favicon and, optionally, an intro animation.
- The brand folder belongs to the wiki, not to the dashboard code. The dashboard only reads it (CON-002).
- Without a brand folder, the dashboard shows its default brand.
- The intro animation is configurable: on or off. When on, it keeps the rules it has today: at most once per browser tab, nothing under reduced motion, done within about two seconds, ends on any click or key, offline.
- The name and the tagline stay where they are, in `_system/wiki.yaml`.

### 5. Two example brands to try

- The product ships two example brands:
  - **Systems42**: the Peaks mark and its intro.
  - **iSAQB atrium**: the atrium mark and its intro.
- Changing one setting switches between them, so people can experiment before they make their own.

### 6. In the Systems42 starter kit

- The starter kit (still to be designed) contains a runnable dashboard with a default configuration.
- A fresh starter kit starts with `make dev` and shows its wiki with the default brand, without editing any file.

## Success metric(s)

- On a clean machine of each system with Docker, a fresh starter kit shows its dashboard after `make dev`, with no other step.
- Switching from the Systems42 brand to the atrium brand takes one changed setting and a reload. The atrium mark and intro then show.
- Turning the intro off takes one changed setting. The home page then opens without it.
- Changing the version a wiki uses and running `make dev` again shows the new version's number on the page.

## Scope

- **In:** releases, start on all three systems with Docker, brand folder, intro on or off, the two example brands, a runnable dashboard in the starter kit.
- **Out, for now:** a start script for Windows, running without Docker as a supported way, hosting the dashboard for many users (CON-001: not production-ready for all circumstances).

## Questions for you

1. Answered: GOAL-002 and a new goal, see **Serves**.
2. Answered: one epic with four features (releases, branding as configuration, example brands, starter kit), plus a constraint "Docker required" and a quality requirement "runs alike on Windows, Linux and macOS" (Q42: flexible, operable).
3. Answered: three keys in `_system/wiki.yaml`: `dashboard_version:` (the release this wiki uses), `brand:` (an example brand, `systems42` or `atrium`, or a folder such as `brand/`), `intro: on | off`.
4. Answered: Windows is ignored for now. No promise for Windows until it is taken up again.
5. Answered: `./dashboard.sh local` stays as an unsupported fallback for developers. Docker is the supported way.
6. Answered: no offline installation for now. Participants start the dashboard once with network before the workshop. After that it runs offline (CON-001).
7. Answered: a container image on GitHub's registry per git tag (`ghcr.io/systems42-org/dashboard:<version>`). `dashboard.sh` starts the version named in `dashboard_version:`. No submodule and no copy of the code in a wiki. Recorded as decision record DR-004, kept short.
