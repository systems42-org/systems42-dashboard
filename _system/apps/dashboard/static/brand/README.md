# Brand slot

Everything that makes the dashboard look like one particular product lives here,
plus one optional template. Replace these files to rebrand it; nothing else needs
to change. The current files are a placeholder: three tiles in the home page's
layout (Requirements and Architecture side by side, Commons below).

## Marks (required)

| File | Where it shows | Rules |
|------|----------------|-------|
| `mark-dark.svg` | Home page hero (5.2rem square) and the top bar on every other page (1.35rem), in the dark theme, which is the default | Square `viewBox`, transparent background, no text. Must stay recognisable at 1.35rem. |
| `mark-light.svg` | The same places in the light theme | The same drawing, coloured for a light background. |
| `favicon.svg` | Browser tab | Must read at 16 px. One colouring for both light and dark tab bars. |

An `<img>` cannot use the page's CSS variables, which is why the marks come in two
colourings. Take the colours from the theme tokens in `../style.css`
(`--area-req`, `--area-arc`, `--area-org`, `--ink`, `--accent`, in their dark and
light values) so the mark belongs to the page.

## Intro animation (optional)

If `templates/_brand_intro.html` exists, the home page includes it before the hero.
If it does not, there is no intro. The file brings its own markup, an inline
`<style>` and a script (inline, or `static/brand/intro.js` loaded with
`{{ static_url('brand/intro.js') }}`). It must:

- show at most once per browser tab (`sessionStorage`), and show every time if
  storage is blocked;
- show nothing when `prefers-reduced-motion: reduce` is set;
- end by itself within about two seconds, and end at once on any click or key;
- start hidden (`hidden` attribute) so a page without JavaScript never shows it,
  and remove its element when done;
- cover the window with `var(--bg)` while it runs, so nothing flashes underneath;
  load its script without `defer`, right after its markup;
- use only theme tokens for colour, so it works in both themes;
- fetch nothing from the network; the dashboard runs offline.

## Visual rules that apply here too

Flat shapes, one border radius (`var(--radius)`), no gradients, no glow, no drop
shadows, no emoji.
