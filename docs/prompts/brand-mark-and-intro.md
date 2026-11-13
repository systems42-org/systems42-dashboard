# Prompt: a mark and an intro animation for a Systems42 dashboard

Fill in the three lines below, then paste everything after the line into a fresh
agent session started in the repository. The prompt is generic: it works for any
Systems42 wiki whose dashboard reads its brand from `brand:` in `_system/wiki.yaml`
(`_system/apps/dashboard/brands/README.md`).

- **Product:** Systems42 Dashboard
- **What it is, in one sentence:** a browsable, read-only view of a requirements
  wiki, shown on a projector in workshops and opened by participants on their own
  devices.
- **Branch to work on:** `brand-mark`

---

You are designing the logo mark and a short intro animation for **{Product}**:
{one sentence}. You work in this repository, on branch `{branch}`, and deliver
files into a fixed slot. Work in four stages, and stop after stage 2 for my choice.

## Stage 1: understand before drawing

Read:
- `_system/apps/dashboard/brands/README.md`: the contract your files must
  meet. It is binding. `brands/systems42/` and `brands/atrium/` are worked examples.
- `_system/apps/dashboard/static/style.css`: the colour tokens at the top, first
  for the dark theme, then for the light theme (`:root[data-theme="light"]`).
- `raw/02-vision.md` and `raw/01-stakeholders.md`: what the product is for and who
  uses it.
- `_system/apps/dashboard/README.md`, sections "Home, areas and tiles" and "Visual
  identity".

Then start the dashboard (`./dashboard.sh local`, http://localhost:8000) and look
at the home page in both themes (Theme is in the ≡ menu). The mark sits next to the
product name in the hero and in the top bar of every other page.

## Stage 2: three concepts, then stop

Propose three different ideas. For each:
- one sentence saying what the mark shows and why that fits the product. Meaning
  comes first: a good mark is a picture of an idea. Example: the iSAQB atrium mark
  is the floor plan of a courtyard with four rooms around it, where the courtyard
  is the association and the rooms are the ways in;
- a rough SVG, rendered to PNG at 16, 32 and 128 px, so we can judge it small;
- one sentence on how the intro animation would move, and how that motion tells
  the same idea.

Show the three side by side in both themes, and stop. I choose, or ask for another
round.

## Stage 3: build the chosen one

**Mark**
- Built on a stated grid (for example 48 × 48 units) with a stated gap and corner
  radius. Write down the coordinates of every part.
- Square, transparent background, no text. Flat colours only: no gradients, glow,
  shadows, outlines or emoji.
- Colours from the theme tokens (`--area-req`, `--area-arc`, `--area-org`, `--ink`,
  `--accent`): one colouring for the dark theme, one for the light theme.
- Recognisable at 16 px (favicon) and at 1.35 rem in the top bar.
- Original: it must not resemble an existing logo, and it uses no other
  organisation's logo or name.
- Deliver `mark-dark.svg`, `mark-light.svg` and `favicon.svg` in a folder of the
  wiki repository, for example `brand/`, and set `brand: brand/` in
  `_system/wiki.yaml`. The dashboard's own files stay as they are.

**Intro animation**
- The mark's own parts move into place. The motion explains the idea; it is not
  decoration.
- About one second of motion, a short hold, then a fade: under two seconds in all.
- Every rule of the contract: once per browser tab, nothing under reduced motion,
  any click or key ends it, hidden until the script shows it, a `var(--bg)` cover,
  no network, theme tokens only.
- Plain JavaScript with SVG or CSS. No library.
- Deliver `intro.html` in the same folder: one self-contained fragment with its
  markup, inline style and inline script.

**Brand page**
- Write `docs/brand/README.md`: the idea, the grid and coordinates, the colours with
  their tokens, the rules (smallest size, clear space, what not to do) and the file
  list.
- Set `about: docs/brand/README.md` in `_system/wiki.yaml`, so the hero mark links
  to it.

Change nothing outside the brand folder, the brand page and `wiki.yaml`: no
template, no shared CSS. If the contract keeps you from doing something good, tell me instead
of working around it.

## Stage 4: check, then show me

- Run the dashboard tests:
  `cd _system/apps/dashboard && for t in tests/test_*.py; do .venv/bin/python "$t" || echo "FAILED: $t"; done`.
  `tests/test_brand.py` checks the example brands against the contract. Point the
  same checks at your folder: hidden by default, placed before the hero, shown once
  per tab, nothing under reduced motion. `test_design_tokens.py` already fails for
  reasons unrelated to your work.
- Screenshots: the home page in both themes at 1280 px and 375 px wide, the top bar
  of a subpage, the favicon at 16 px, and frames of the animation at 0, 25, 50, 75
  and 100 %.
- Confirm that with reduced motion turned on, no intro shows.

Then show me the screenshots and the list of changed files. Commit on the branch
only when I say so.
