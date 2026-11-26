# Helix Brand Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The shipped brand `systems42` shows the helix logo with an intro that ends on "systems42 / dashboard"; the Chart mark is archived as a usable brand folder.

**Architecture:** Brand files only: SVG marks and an HTML intro fragment in `_system/apps/dashboard/brands/systems42/`, served unchanged by the Python and the Go dashboard. The helix files come from the meta repository. A throwaway script turns "dashboard" (and, for the lockups, "systems42") into SVG paths from the dashboard's own Bricolage Grotesque font.

**Tech Stack:** SVG, HTML/CSS/JS fragment, plain-script Python tests (no pytest), fontTools (one-off, via `uv run --with`), `rsvg-convert` for PNGs.

**Spec:** `docs/superpowers/specs/2026-11-26-helix-brand-design.md`

## Global Constraints

- Work on branch `brand/helix`; deliver as one PR. Never stage `_system/wiki.yaml`, `_system/index.md`, `_system/log.md` or `wiki/issues/ISS-009-*` (unrelated uncommitted changes).
- Helix source: meta repository, commit `0b87027`, folder `brand/`: `git -C ../meta show 0b87027:brand/<file>`. Marks and favicon are copied byte for byte.
- Brand contract (`_system/apps/dashboard/brands/README.md`): marks square and text-free; intro sandboxed, no font loading, no external URL, colours only as theme tokens or `--brand-*` tokens declared once per theme.
- "dashboard" line: Bricolage Grotesque weight 700, letter-spacing -0.02em, as paths, fill `var(--ink)`, height about 0.55 of the "systems42" line, left-aligned with it, rises at 1.35 s with `bi-rise`.
- Intro timers: fade class at 2150 ms, `done` at 2400 ms.
- Chart archive path: `docs/brand/archive/chart/`.
- No `VERSION` bump: the release is a separate step by the maintainer.
- Text follows `_system/writing-style.md`. Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Light theme: "dashboard" must be readable on the light `--bg`; it uses `var(--ink)`, never a literal colour (Task 2 test on hex lines; visual check in both themes).
2. A 375 px wide window: the two-line wordmark must not overflow sideways (Task 2 visual check).
3. The `/about` page of this wiki renders `docs/brand/README.md`: every image it references must exist (Task 3 test).
4. The archived Chart folder must still be a valid brand a wiki can select (Task 1 test).
5. `make site` exports `/brand/intro.html` and the marks; it must still build (Task 4).

---

### Task 1: Archive the Chart mark, ship the helix marks and favicon

**Files:**
- Move: `_system/apps/dashboard/brands/systems42/{favicon.svg,intro.html,mark-dark.svg,mark-light.svg}` → `docs/brand/archive/chart/`
- Move: `docs/brand/{README.md,favicon.png,lockup-dark.png,lockup-dark.svg,lockup-light.png,lockup-light.svg,mark-dark.png,mark-light.png}` → `docs/brand/archive/chart/`
- Create: `docs/brand/archive/README.md`
- Create: `_system/apps/dashboard/brands/systems42/{mark-dark.svg,mark-light.svg,favicon.svg}` (from meta)
- Test: `_system/apps/dashboard/tests/test_brand.py`

**Interfaces:**
- Produces: `brands/systems42/mark-*.svg` and `favicon.svg` with viewBox `5.36 13.97 32.03 32.03`; `docs/brand/archive/chart/` as a complete brand folder.

- [ ] **Step 1: Create branch** `git switch -c brand/helix`.

- [ ] **Step 2: Write the failing tests** in `test_brand.py`, and add both to the `__main__` list:

```python
ARCHIVE = _HERE.parents[2] / "docs" / "brand" / "archive" / "chart"

def test_the_shipped_marks_are_the_helix():
    """FR-032: the shipped brand is the helix of the systems42 logo."""
    light = (BRANDS / "systems42" / "mark-light.svg").read_text(encoding="utf-8")
    dark = (BRANDS / "systems42" / "mark-dark.svg").read_text(encoding="utf-8")
    assert 'viewBox="5.36 13.97 32.03 32.03"' in light and 'viewBox="5.36 13.97 32.03 32.03"' in dark
    assert "#0f7f66" in light and "#1667c4" in light
    assert "#199c7e" in dark and "#3a86e6" in dark
    for name in MARKS:
        assert "Chart" not in (BRANDS / "systems42" / name).read_text(encoding="utf-8"), name

def test_the_chart_mark_is_archived_as_a_brand_folder():
    names = {p.name for p in ARCHIVE.iterdir()}
    assert {"mark-dark.svg", "mark-light.svg", "favicon.svg", "intro.html", "README.md"} <= names
    assert 'class="bi-block' in (ARCHIVE / "intro.html").read_text(encoding="utf-8")
```

- [ ] **Step 3: Run** `cd _system/apps/dashboard && .venv/bin/python tests/test_brand.py`. Expected: FAIL in `test_the_shipped_marks_are_the_helix` (Chart marks still shipped).

- [ ] **Step 4: Move and copy.** `git mv` the files listed above. Then, for each of `mark-dark.svg mark-light.svg favicon.svg`: `git -C ../meta show 0b87027:brand/$f > _system/apps/dashboard/brands/systems42/$f`. Write `docs/brand/archive/README.md`: two to four sentences: the Chart mark was the shipped brand from 2026-11-23 to 2026-11-26; `chart/` is a complete brand folder; to use it, copy `chart/` to a wiki's `brand/` and set `brand: brand/` in `_system/wiki.yaml`. Leave `brands/systems42/intro.html` absent for now (Task 2 creates it).

- [ ] **Step 5: Run** the test script. Expected: the two new tests pass; `test_the_shipped_intro_is_the_chart_mark` and the intro tests fail because `intro.html` is missing. This is expected until Task 2; do not commit yet.

### Task 2: Intro with the "dashboard" line

**Files:**
- Create: `_system/apps/dashboard/brands/systems42/intro.html`
- Create (throwaway, scratchpad, not committed): `wordpaths.py`
- Modify: `_system/apps/dashboard/tests/test_brand.py` (replace `test_the_shipped_intro_is_the_chart_mark` and `test_systems42_intro_ends_within_two_seconds`)

**Interfaces:**
- Consumes: helix paths in meta's `intro.html` (`0b87027`).
- Produces: `wordpaths.py TEXT` printing `viewBox` and one `<path d=…>` per letter; reused by Task 3.

- [ ] **Step 1: Write the failing tests**, replacing the two old ones (update the `__main__` list):

```python
def test_systems42_intro_ends_within_two_and_a_half_seconds():
    text = intro("systems42")
    assert "setTimeout(done, 2400)" in text
    assert "classList.add('bi-out'); }, 2150)" in text

def test_the_shipped_intro_is_the_helix_with_a_dashboard_line():
    """FR-032: the helix winds up, "systems42" rises in, then "dashboard"."""
    text = intro("systems42")
    assert text.count('class="bi-strand') == 2, "green and blue strand"
    assert text.count('class="bi-word"') == 1
    sub = re.search(r'<svg class="bi-sub"[^>]*>(.*?)</svg>', text, re.S)
    assert sub and sub.group(1).count("<path") == 9, "d a s h b o a r d"
    assert "bi-block" not in text and "bi-axis" not in text
    assert sorted(p.name for p in (BRANDS / "systems42").iterdir()) == \
        ["favicon.svg", "intro.html", "mark-dark.svg", "mark-light.svg"]
```

- [ ] **Step 2: Run** the test script. Expected: FAIL (`intro.html` missing).

- [ ] **Step 3: Write `wordpaths.py`** in the scratchpad, run as `uv run --with fonttools --with brotli python -I wordpaths.py FONT TEXT`. Approach: `instancer.instantiateVariableFont(TTFont(FONT), {"wght": 700})`; for each character, draw its glyph with `SVGPathPen` through a `TransformPen` scaling by `100/unitsPerEm` with y flipped; advance x by `advance*100/upm - 2` (−0.02em). Print `viewBox="0 -73 {width:.1f} 100"` and the paths with two decimals. FONT is `_system/apps/dashboard/static/vendor/fonts/BricolageGrotesque-var.woff2`.

- [ ] **Step 4: Check the script against meta.** Run it with `systems42`. Expected: width within 1 unit of meta's `494.4`. If not, fix the script before going on.

- [ ] **Step 5: Build `intro.html`** from meta's `intro.html` at `0b87027`:
  - Update the opening comment: say it is the systems42 helix intro of the dashboard, with "dashboard" as the second line, about 2.4 s.
  - Wrap `.bi-word` and a new `<svg class="bi-sub" viewBox=… focusable="false">` (nine `<path style="--i:N">`, from `wordpaths.py dashboard`) in `<div class="bi-lines">`, a column flex with `align-items: flex-start` and a small gap.
  - CSS: `.bi-sub` height `clamp(1.2rem, 5vw, 2.2rem)`, width auto, `overflow: visible`; `.bi-sub path` fill `var(--ink)`, opacity 0, `bi-rise .4s` with delay `calc(1.35s + var(--i) * .03s)`.
  - Timers: `bi-out` at 2150, `done` at 2400.
  - Keep helix paths, colours and the "systems42" timing unchanged.

- [ ] **Step 6: Run** the test script. Expected: `OK: shipped brand`.

- [ ] **Step 7: Check by eye.** `make app-start`, open the home page in a fresh tab in the dark theme, then in the light theme, then with the window 375 px wide. Expected: helix winds up, "systems42" rises, "dashboard" appears below, left-aligned, readable, no sideways overflow; the intro is gone after about 2.4 s.

- [ ] **Step 8: Commit** (Tasks 1 and 2 together, since Task 1 alone leaves the brand without an intro):

```bash
git add _system/apps/dashboard/brands docs/brand/archive _system/apps/dashboard/tests/test_brand.py
git commit -m "Dashboard brand: the helix replaces the Chart mark, the Chart is archived"
```

### Task 3: Brand page and lockups

**Files:**
- Create: `docs/brand/README.md`, `docs/brand/{lockup-dark,lockup-light}.svg`, `docs/brand/{mark-dark,mark-light,favicon,lockup-dark,lockup-light}.png`
- Modify: `_system/apps/dashboard/brands/README.md:15-16`
- Test: `_system/apps/dashboard/tests/test_brand.py`

**Interfaces:**
- Consumes: `wordpaths.py` (Task 2), the helix marks (Task 1).

- [ ] **Step 1: Write the failing test** (add to `__main__`):

```python
def test_the_brand_page_shows_only_files_that_exist():
    """docs/brand/README.md is this wiki's /about page."""
    docs = _HERE.parents[2] / "docs" / "brand"
    for folder in (docs, ARCHIVE):
        text = (folder / "README.md").read_text(encoding="utf-8")
        for src in re.findall(r'src="([^"]+)"', text):
            assert (folder / src).is_file(), (folder, src)
    assert "helix" in (docs / "README.md").read_text(encoding="utf-8").lower()
```

- [ ] **Step 2: Run** the test script. Expected: FAIL (`docs/brand/README.md` missing).

- [ ] **Step 3: Lockups.** `lockup-light.svg` and `lockup-dark.svg`: the helix (light/dark mark paths) at 56 units height on the left, right of it "systems42" (ink, "42" in `--brand-req` green) over "dashboard" (ink, 0.55 the size), both from `wordpaths.py`. Light ink `#14213c`, dark ink `#e8eef9`; greens and blues as in the marks. Opening comment says what it is and that the dashboard never shows it.

- [ ] **Step 4: PNGs.** `rsvg-convert -h 256` for marks and favicon, `-h 96` for lockups.

- [ ] **Step 5: `docs/brand/README.md`**: title "Systems42 Dashboard: the helix"; the idea in two sentences (the green req42 strand and the blue arc42 strand wound into one; same logo as systems42, from meta); colour table (part, dark, light) with the four values; favicon line; rules (no text in the mark, transparent background, no recolouring); intro in one sentence (helix winds up, "systems42" rises letter by letter, then "dashboard", about 2.4 s, once per tab, skipped under reduced motion); lockup with the two PNG previews in the same `<div>` layout as before; files paragraph; one line linking `archive/README.md` for the Chart mark.

- [ ] **Step 6: `brands/README.md`**: line 15 reads "`brand: systems42` is the helix of the systems42 logo and its intro (the default, also when `brand:` is missing)." The rest unchanged.

- [ ] **Step 7: Run** the test script. Expected: `OK: shipped brand`. Open `docs/brand/lockup-light.png` and `lockup-dark.png` and check the layout by eye.

- [ ] **Step 8: Commit** `git add docs/brand/README.md docs/brand/*.svg docs/brand/*.png _system/apps/dashboard/brands/README.md _system/apps/dashboard/tests/test_brand.py` with message "Brand page: the helix, its lockups and the archived Chart mark".

### Task 4: Changelog, capture note, full checks, PR

**Files:**
- Modify: `CHANGELOG.md` (Unreleased)
- Create: `raw/2026-11-26-the-helix-replaces-the-chart-mark.md`
- Add: `docs/superpowers/specs/2026-11-26-helix-brand-design.md`, `docs/superpowers/plans/2026-11-26-helix-brand.md`

- [ ] **Step 1: CHANGELOG** entry under Unreleased, as one bullet in the style of the Chart mark entry: "Dashboard brand: the helix of the systems42 logo replaces the Chart mark (FR-032)…", naming the intro ending on "systems42 / dashboard", the archive path, and that every wiki without a brand of its own switches on update. Name the open follow-ups: website hero, Mac app icon (#172).

- [ ] **Step 2: Capture note** in `raw/`: what was decided on 2026-11-26 by the maintainer (helix becomes the default for every wiki; Chart archived, not shipped; "dashboard" as second line in the intro and lockups; source meta#73), and that FR-032's first two bullets and its history need the change. Plain facts, no wiki edits.

- [ ] **Step 3: Run all tests** `make test`. Expected: every script passes, including the Go parity test.

- [ ] **Step 4: Build the site** `make site`. Expected: build finishes without check errors; `site/_site/demo/brand/intro.html` contains `bi-sub`.

- [ ] **Step 5: Commit** the changelog, the note, the spec and the plan with message "Helix brand: changelog, capture note, design and plan".

- [ ] **Step 6: Push and open the PR** `git push -u origin brand/helix`, `gh pr create` with a body listing what changed, the follow-ups and the test results, ending with the attribution line. Do not merge.
