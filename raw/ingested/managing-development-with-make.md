# Managing development with make

Raised by Gernot Starke on 2026-11-21. Not yet captured into `wiki/`.

**Requirement.** Maintainers and contributors manage day-to-day development, testing, site previews and releases of the Systems42 dashboard through short `make` targets at the repository root.

**For.** Maintainers and developers working on the dashboard repository, and operators starting a wiki from the command line.

## Needed for development

The root `Makefile` stays a thin wrapper over `dashboard.sh`, `_system/apps/dashboard/dev.sh` and the scripts under `site/`. Running `make` with no arguments prints the list of targets and what each one does (`help`).

### Running the dashboard

- `make dev`: start the dashboard release named in `_system/wiki.yaml` in Docker and open the browser (`./dashboard.sh up`).
- `make uv`: start the same release with `uv` instead of Docker in the foreground, stopped by Ctrl+C (`./dashboard.sh uv`).
- `make app-start`: build and start the Go implementation of the dashboard without Docker in the foreground, stopped by Ctrl+C (`./dashboard.sh app-start`, dashboard repository only).
- `make down`: stop and remove the running dashboard container (`./dashboard.sh down`).

### Testing and cleaning

- `make test`: run the dashboard's test scripts inside the Docker test stage (`./dashboard.sh test`, dashboard repository only).
- `make clean`: remove rebuildable artifacts (containers, local `.venv`, `__pycache__`, `.DS_Store`) without touching human-owned content (`wiki/`, `raw/`, `docs/`, `sandbox/`).

### Public website (`dashboard.systems42.org`)

- `make site`: build the static site into `site/_site/` in Docker (`./site/build.sh`).
- `make site-show`: serve `site/_site/` in Docker and open the browser, building first if missing (`./site/serve.sh up`).
- `make site-down`: stop the local site preview container (`./site/serve.sh down`).

### Releases

- `make version V=X.Y.Z`: raise `_system/apps/dashboard/VERSION`, update `CHANGELOG.md` and open a release pull request (`./dashboard.sh version $(V)`, dashboard repository only).
- `make publish`: run the test suite and push the git tag for the version on `main` (`./dashboard.sh publish`, dashboard repository only).

## Constraints and expectations

- Every target is documented in `make help` and delegates its real logic to scripts so the `Makefile` stays easy to read.
- Repository-only development targets (`app-start`, `test`, `version`, `publish`) stay clearly distinguished from targets every Systems42 wiki uses (`dev`, `uv`, `down`, `clean`).
- Development commands never modify human-owned wiki content (`wiki/`, `raw/`), keeping CON-002 intact.
