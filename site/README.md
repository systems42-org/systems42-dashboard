# Public website (`dashboard.systems42.org`)

Static showcase, documentation, downloads and interactive `/demo/` export for the Systems42 Dashboard, deployed directly from `site/_site/` via GitHub Actions (no `gh-pages` branch).

## Build and preview locally

Build into `site/_site/` (gitignored, runs in Docker):

```sh
make site
```

Preview locally in Docker (no local Python required; builds first if needed and opens your browser):

```sh
make site-show
make site-down
```

Set `SITE_PORT=8091` if port `8090` is already in use. Nothing in `wiki/`, `raw/`, `_system/`, `_templates/` or `docs/` is modified.

## Switching the demo wiki (for example to `isaqb-atrium`)

By default `make site` exports this repository's own wiki under `/demo/`. To export another Systems42 wiki instead:

```sh
make site DEMO_WIKI=/path/to/isaqb-atrium
```

In GitHub Actions (`.github/workflows/site.yml`), set the repository variable `SITE_DEMO_WIKI_REPO` (or pass `demo_wiki_repo` on manual dispatch, for example `systems42-org/isaqb-atrium`) to switch the live demo on `dashboard.systems42.org`.

## GitHub Pages & DNS setup

1. In GitHub repository **Settings → Pages**, set **Source** to **GitHub Actions**.
2. Set **Custom domain** to `dashboard.systems42.org` and enable **Enforce HTTPS** once the certificate is issued.
3. At Namecheap (**Advanced DNS** for `systems42.org`), add a `CNAME Record` with Host `dashboard` pointing to `systems42-org.github.io.`.
4. Merging to `main` (or triggering the `site` workflow manually) builds `site/_site/` and deploys it to GitHub Pages.
