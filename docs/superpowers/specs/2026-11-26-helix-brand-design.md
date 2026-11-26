# The helix replaces the Chart mark as the shipped brand

Approved by the maintainer on 2026-11-26.

## Intent

The systems42 founders adopted a new logo, the helix (meta repository, `brand/`, [meta#73](https://github.com/systems42-org/meta/pull/73)). The dashboard's shipped brand `systems42` takes it over and becomes the default for every wiki without a brand of its own. The Chart mark stays available for history.

## Goals

- `brands/systems42/` holds the helix: marks, favicon and intro.
- The intro shows the wordmark in two lines: "systems42", then "dashboard".
- The Chart mark is archived as a complete brand folder that a wiki can copy into its `brand/`.

## Non-goals

- The website's hero landscape (`site/static/chart.svg`, `site/static/site.css`). Follow-up.
- The Mac app icon, still the Peaks mark ([#172](https://github.com/systems42-org/systems42-dashboard/issues/172)). Follow-up.
- A second shipped brand `chart`: rejected, the Chart mark is archived instead.

## Constraints

- The brand contract in `_system/apps/dashboard/brands/README.md`: marks without text, intro sandboxed, no font loading, removed after 4 s at the latest.
- Every wiki without its own `brand:` folder switches to the helix on update. The changelog says so.
- `_system/` changes go through a PR. FR-032 changes through a capture of a `raw/` note.

## Approaches

1. **Take meta's files, add one line to the intro (chosen).** One source for the helix, little new drawing.
2. **Ship the Chart as a second brand `brand: chart`.** Rejected: more to maintain in every release, and FR-032 would change scope for a mark kept only for history.
3. **Redraw the helix for the dashboard.** Rejected: two diverging copies of one logo.

## Design

1. `git mv` the four files of `brands/systems42/` and all files of `docs/brand/` into `docs/brand/archive/chart/`. A short README there says how to use it as a wiki brand.
2. Copy `mark-dark.svg`, `mark-light.svg` and `favicon.svg` from meta `origin/main` unchanged into `brands/systems42/`.
3. `intro.html` is meta's intro plus a second SVG line "dashboard": Bricolage Grotesque weight 700 as paths (from `static/vendor/fonts/BricolageGrotesque-var.woff2`), fill `var(--ink)`, about 0.55 of the height of "systems42", left-aligned with it. It rises at 1.35 s with the same `bi-rise` animation. Fade at 2.15 s, removal at 2.4 s.
4. `docs/brand/README.md` describes the helix, with lockups `lockup-dark.svg`/`lockup-light.svg` (helix, "systems42", "dashboard") and PNGs of marks, favicon and lockups.
5. `tests/test_brand.py` checks for the helix instead of the Chart columns. `brands/README.md` line 15 names the helix.
6. `CHANGELOG.md` entry under Unreleased. A `raw/` note for the FR-032 capture.

## Left to the builder

- Exact size, spacing and alignment of the "dashboard" line, checked by eye in both themes.
- PNG sizes, as in the archived `docs/brand/`.
