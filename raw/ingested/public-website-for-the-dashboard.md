# A public website for the dashboard

Stated by Gernot Starke on 2026-11-21. The details below were read from the existing site (`site/`, published at `dashboard.systems42.org`) on the same day and rewritten as requirements. Nobody has agreed the single points yet. "Today" describes what the site does. "Gaps" and "Open questions" were found while reading and were not discussed.

**Requirement.** The dashboard needs a public website. A person who has never seen the dashboard learns there what it is, tries it on a real wiki without installing anything, and finds what they need to run it on their own wiki.

**Why.** Until now a person had to clone a repository and start Docker before seeing a single page. That is too much to ask from someone who only wants to know whether the dashboard is worth a look.

**For.** People who consider using Systems42 or its dashboard, people who set up a project wiki and run its dashboard, people learning or presenting Systems42, and maintainers who publish a release.

## What the site shall contain

### 1. Overview

- The site says in one sentence what the dashboard is: a read-only view in the browser of a requirements and architecture wiki written in Markdown.
- It names what a reader can do with it: search that forgives typos, tracing from goals to requirements and building blocks, and one shared view in a workshop.
- From the first screen a visitor reaches the demo, the downloads and the documentation with one click each.
- It shows the current release number.
- It shows the two steps to start the dashboard on one's own wiki: get the launcher and name a release in `_system/wiki.yaml`, then start it.

### 2. A demo to try

- The site holds a demo of the real dashboard on a real Systems42 wiki. A visitor uses it in the browser, with no installation and no account.
- The demo is a snapshot made from the dashboard itself, not a rebuilt copy. What the demo shows is what a release shows.
- In the demo a visitor can read every page, search, sort and filter lists, switch the theme, and use the diagrams, including the metamodel and the term network.
- What needs a running dashboard is left out of the demo: joining by QR code, the list of connected tabs, the View dialog, Reload and Disconnect all. The demo says that it is a static, read-only demo.
- Every demo page offers a way back to the site, its documentation and its downloads.
- The overview names the demo's wiki and says how many wiki pages and views it holds.
- The overview points to single things worth trying, each with a link into the demo: search, goals and the goal coverage matrix, requirements and open issues, the metamodel and graphs, the method overview.
- The maintainers can choose which Systems42 wiki the demo shows, without changing the site. By default it is the dashboard's own wiki.

### 3. Downloads

- A visitor can download the launcher (`dashboard.sh`), with its SHA-256 checksum next to it.
- The page names the container image of the current release with the command to pull it, says which processor types it supports (amd64, arm64), and that no registry login is needed.
- It links to the releases and the source on GitHub and names the command that moves a wiki to the newest release.
- It gives commands to copy: getting the launcher with `curl`, and a minimal `_system/wiki.yaml`.
- It states the supported platforms and the limits: Linux and macOS, offline after the first start, no login, no write access to the wiki, for local reading and trusted workshop rooms.
- It shows the release notes of the newest releases, taken from `CHANGELOG.md`.

### 4. Documentation

- The page explains the keys of `_system/wiki.yaml`: `system_name`, `tagline`, `dashboard_version`, `brand`, `intro`, `about`, each with its purpose and an example.
- It explains what a Systems42 wiki must hold for the dashboard to show it.
- It explains branding by configuration: the files of a brand folder, the rules for the intro, and that a missing or incomplete brand falls back to the shipped one.
- It explains a workshop session: starting on the facilitator's laptop, joining by QR code, the Keyholder, the View, Disconnect all, and that the dashboard stops when the last tab closes.
- It states that the dashboard is read-only and has no login, so a live session belongs on a trusted network, and that the static export is the way to publish a wiki for reading.
- It holds the Getting Started guide and the brand prompt template as pages of their own, taken from `docs/` of the repository.

### 5. Legal and project information

- The site has an imprint that meets German law (§ 5 DDG).
- It has a privacy notice that says who hosts the site, which access data the host may record, and what the demo stores in the visitor's browser.
- The site sets no cookies and loads no tracking, analytics or advertising scripts.
- Every page links to the repository, the releases and the issue tracker on GitHub, and to the method family: systems42.org, arc42.org, docs.arc42.org, req42.de, quality.arc42.org.

### 6. On every page

- A header with the name, the release number and the navigation: Overview, Docs, Downloads, GitHub, Live Demo.
- A footer with the release number and the date the site was built.
- The site is usable on a phone.
- The site is in English.

### 7. Building and publishing

- The site is built from the repository: the release number, the launcher, the changelog, the guides and the demo come from their one source, and nothing is written by hand a second time.
- Building the site changes nothing in `wiki/`, `raw/`, `_system/`, `_templates/` or `docs/`.
- A change on `main` publishes the site without a manual step. A maintainer can also publish by hand.
- The build fails when a required page is missing, when a link inside the site leads nowhere, or when a demo page still tries to reach a running dashboard.
- A maintainer can build the site and look at it locally before it is published.
- The site is reachable at `dashboard.systems42.org` over HTTPS.

## Today

- `make site` builds the site into `site/_site/` in Docker. `make site-show` serves it locally, `make site-down` stops that.
- `site/build.py` exports the demo by asking the dashboard for every page it links, and rewrites the addresses to `/demo/`.
- `.github/workflows/site.yml` builds and publishes the site to GitHub Pages on every push to `main` and on request.
- `DEMO_WIKI=/path` (locally) or the repository variable `SITE_DEMO_WIKI_REPO` (on GitHub) chooses the demo's wiki.
- The pages are Overview, Downloads, Docs with Getting Started and Brand Prompt, Imprint & Privacy, and the demo.

## Gaps

- The site names Docker as the only way to start the dashboard. The start with uv (FR-054) and the planned app (FR-055) are missing from Overview, Downloads and Docs.
- The Downloads page offers no wheel and says nothing about a machine without a container engine.
- The site has no tests in the test suite. Its only checks are those the build runs on its own output.
- The wiki has no requirement, stakeholder or goal for the site. "People who consider using Systems42" were dropped as a stakeholder on 2026-11-19 (STK-022), and the site is made for them.
- The site is a second public statement of what the dashboard does, next to the README and the help page. Nothing checks that the three agree.

## Open questions

- Which goal does the site serve: GOAL-002 (show what Systems42 can do), GOAL-008 (one way into every Systems42 wiki), or a new one?
- Is the static export a feature for every wiki ("publish my wiki for reading"), or only the way this site gets its demo? The Docs page already recommends it for publishing.
- Which wiki shall the demo show in the long run: the dashboard's own, or a richer one such as isaqb-atrium?
- CON-001 says the dashboard is not for public networks. The demo is public. It is a snapshot without a server, but the wiki it shows becomes public with it. Who decides that a wiki may be shown?
- Does the site need a measure, for example how fast the overview loads on a phone, or that it stays reachable?
- Who keeps the imprint and the privacy notice correct?
