# The helix replaces the Chart mark

Decisions of the maintainer, 2026-11-26, in a Claude Code session on this repository.

1. The systems42 founders adopted a new logo, the helix: a green req42 strand and a blue arc42 strand wound into one, with the wordmark "systems42" ("42" in green). Source: Systems42 meta repository, `brand/`, [meta#73](https://github.com/systems42-org/meta/pull/73).
2. The helix becomes the dashboard's shipped brand `systems42`, the default for every wiki without a brand of its own. The maintainer knows that such wikis change their look on update; release 0.11.3 had done the same with an earlier logo and was reverted.
3. Marks and favicon are taken from meta unchanged. The intro is meta's intro with "dashboard" as a second line under "systems42". The lockups on the brand page show "systems42" over "dashboard".
4. The Chart mark is kept for history, archived as a complete brand folder in `docs/brand/archive/chart/`, not shipped as a second brand. A wiki that wants it copies the folder into its `brand/`.
5. Left for later: the website's hero still shows the Chart columns; the Mac app icon still shows the peaks (issue #172).

Affected in the wiki: FR-032 (its first two bullets describe the Chart mark; its history needs the change), and the brand descriptions that name the Chart mark.

Implemented on branch `brand/helix`.
