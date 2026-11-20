# Public website (`dashboard.systems42.org`)

Static showcase, documentation, downloads and interactive `/demo/` export for the Systems42 Dashboard, published to GitHub Pages via the `gh-pages` branch.

## Build locally

```sh
make site
```

This runs `site/build.py` inside Docker (using the dashboard's `base` image stage) and writes the finished site to `site/_site/` (gitignored). Nothing in `wiki/`, `raw/`, `_system/`, `_templates/` or `docs/` is modified.

Preview locally:

```sh
python3 -m http.server 8090 --directory site/_site
```

## Switching the demo wiki (for example to `isaqb-atrium`)

By default `make site` exports this repository's own wiki under `/demo/`. To export another Systems42 wiki instead:

```sh
make site DEMO_WIKI=/path/to/isaqb-atrium
```

In GitHub Actions (`.github/workflows/site.yml`), set the repository variable `SITE_DEMO_WIKI_REPO` (or pass `demo_wiki_repo` on manual dispatch, for example `systems42-org/isaqb-atrium`) to switch the live demo on `dashboard.systems42.org`.

## One-time GitHub Pages setup

1. In GitHub repository **Settings → Pages**, set **Source** to **Deploy from a branch**, branch `gh-pages`, folder `/ (root)`.
2. Point DNS for `dashboard.systems42.org` with a `CNAME` record to `systems42-org.github.io`.
3. Enable **Enforce HTTPS** once GitHub issues the certificate.
