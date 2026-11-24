# Public website (`dashboard.systems42.org`)

Static showcase, documentation, downloads and interactive `/demo/` export for the Systems42 Dashboard, deployed directly from `site/_site/` via GitHub Actions (no `gh-pages` branch).

## How the site is built

The site has its own build, `site/build.py`. It is a Python script, and it uses no site generator. `make site` runs it in the dashboard's Docker image (`site/build.sh`), so it needs Docker and no local Python. The script does five things, in this order:

1. **Demo.** It loads the dashboard's own code (`_system/apps/dashboard/app.py`) on the demo wiki and asks it for every page, starting from a list of routes and following the links it finds. Each page is saved as a file under `/demo/`, with its links rewritten and everything removed that needs a running dashboard (joining, connected tabs, View dialog, Reload). The dashboard filters its issue list on the server, so the exported list holds every issue and `site/demo/issue-filters.js` filters it in the browser from the address.
2. **Files.** It copies the site's stylesheet, the marks of the `systems42` brand, `dashboard.sh` and `CNAME`, and works out the SHA-256 checksum of `dashboard.sh`.
3. **Pages.** It renders the pages of the site from the Jinja templates in `site/templates/`: overview, downloads, docs and imprint. The release number comes from `_system/apps/dashboard/VERSION`, the changelog excerpt from `CHANGELOG.md`.
4. **Guides.** It renders four Markdown files from `docs/` as pages under `/docs/`: `INSTALL.md`, `GETTING-STARTED.md`, `prompts/brand-mark-and-intro.md` and `go-dashboard-requirements-summary.md`.
5. **Checks.** It fails when a required page is missing, when a link inside the site leads nowhere, when a demo page still calls a running dashboard, when a demo script navigates outside `/demo/`, or when the demo's issue list cannot filter in the browser.

The result is the folder `site/_site/`. The `site` workflow (`.github/workflows/site.yml`) runs the same `make site` and hands that folder to GitHub Pages as it is. GitHub does no build of its own.

The workflow publishes the site on every push to `main` and once more after every release, when the downloads of the new release exist. On a pull request it builds the site and runs the checks, without publishing.

To put a new guide on the site, add its Markdown file to `docs/`, add one `write_page(...)` call in `build_site()` and link it from `site/templates/docs.html`.

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
