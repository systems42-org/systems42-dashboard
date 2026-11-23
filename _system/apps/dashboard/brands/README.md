# Brands

A brand is what makes the dashboard look like one particular product: two
marks, a favicon and, if wanted, an intro animation on the home page. A wiki
picks its brand in `_system/wiki.yaml`. Nothing in the dashboard's code or
templates changes.

```yaml
brand: systems42   # the brand from this folder, or a folder of your own
intro: on          # off: the home page shows no intro, whatever the brand has
```

## Choosing a brand

- `brand: systems42` is the Chart mark and its intro (the default, also when
  `brand:` is missing). The mark is described in `docs/brand/README.md`.
- `brand: brand/` is a folder of your own, relative to the wiki repository
  root. The dashboard only reads it and serves its marks at `/brand/<file>`.

Switching is one changed key and a browser reload. A folder outside the wiki
repository (`..`, an absolute path, a symlink pointing out), a missing folder
or one without all three marks shows the default brand instead, and the
dashboard logs a warning.

## Files in a brand folder

| File | Where it shows | Rules |
|------|----------------|-------|
| `mark-dark.svg` (required) | Home page hero (5.2rem square) and the top bar on every other page (1.35rem), in the dark theme, which is the default | Square `viewBox`, transparent background, no text. Must stay recognisable at 1.35rem. |
| `mark-light.svg` (required) | The same places in the light theme | The same drawing, coloured for a light background. |
| `favicon.svg` (required) | Browser tab | Must read at 16 px, on light and dark tab bars. A `prefers-color-scheme` rule inside the SVG may switch colours. |
| `intro.html` (optional) | Home page, before the hero | See below. |

An `<img>` cannot use the page's CSS variables, which is why the marks come in two
colourings. Take the colours from the theme tokens in `../static/style.css`
(`--area-req`, `--area-arc`, `--area-org`, `--ink`, `--accent`, in their dark and
light values) so the mark belongs to the page.

## Intro animation (optional)

`intro.html` is one self-contained HTML fragment: its markup, an inline
`<style>` and an inline `<script>`. It is not a template, so `{{ }}` stays
literal text. Without the file, or with `intro: off`, there is no intro.

The home page shows the intro in a frame over the whole window, before the
hero. The frame is sandboxed: the intro's script runs in an origin of its own.
It cannot read or change the dashboard page, cannot call the dashboard and
cannot load anything. `sessionStorage` and `localStorage` throw there. The
frame's document holds the theme tokens (the `:root` blocks of
`../static/style.css`) and nothing else of the dashboard's styles or fonts.

The home page does this for every intro:

- it shows the intro at most once per browser tab, and every time if storage
  is blocked;
- it shows nothing when `prefers-reduced-motion: reduce` is set;
- it takes the frame away when the intro has removed its element, on any key,
  and at the latest after 4 seconds.

The intro must:

- end by itself within about two seconds, and end at once on any click;
- start hidden (`hidden` attribute) and remove its element when done. That
  removal is the sign that the intro is over. An intro that never shows its
  element counts as over too;
- cover the window with `var(--bg)` while it runs, and fade itself out at the
  end, so the page appears underneath;
- use the theme tokens for colour, so it works in both themes. A colour of the
  brand's own that no token has is declared once as a `--brand-*` custom
  property on the intro's element, for the dark theme and again under
  `:root[data-theme="light"]`, and used through `var()`;
- fetch nothing from the network; the dashboard runs offline.

`systems42/intro.html` is a worked example.

The dashboard does not trust a brand folder. The marks are served without
script, and the intro's script runs in every viewer's browser, but in the
sandboxed frame, without the dashboard's rights. What an intro can still do is
draw over the home page for up to 4 seconds, so look at a brand folder before
you commit it.

## Visual rules that apply here too

Flat shapes, one border radius (`var(--radius)`), no gradients, no glow, no drop
shadows, no emoji.
