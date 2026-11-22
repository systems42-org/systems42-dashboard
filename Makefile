# Thin wrapper around dashboard.sh, the launcher: `make dev` instead of
# `./dashboard.sh up`. `./dashboard.sh logs|update` have no target here; call
# the script directly.
#
# `make app-start`, `make app-bundle`, `make test`, `make site*`, `make version` and `make publish` work only in the dashboard's own repository,
# which holds the dashboard code (`./dashboard.sh rebuild|local|app-start|app-bundle|test|version|publish`,
# see _system/apps/dashboard/dev.sh).

.DEFAULT_GOAL := help

.PHONY: help dev uv app-start app-bundle down clean test site site-show site-down version publish

help::
	@echo "In every Systems42 wiki:"
	@echo "  make dev        start the dashboard release this wiki names (Docker), opens your browser"
	@echo "  make uv         start the same release with uv instead of Docker; Ctrl+C stops it"
	@echo "  make down       stop the dashboard"
	@echo "  make clean      remove what can be rebuilt (container, caches); never content"
	@echo ""
	@echo "In the dashboard's repository only:"
	@echo "  make app-start  build and start the Go dashboard without Docker; Ctrl+C stops it"
	@echo "  make app-bundle build the macOS Systems42 Dashboard.app and DMG into dist/ (macOS only)"
	@echo "  make test       run the dashboard's test scripts (Docker)"
	@echo "  make site       build the static dashboard.systems42.org site into site/_site/ (Docker)"
	@echo "  make site-show  serve site/_site/ in Docker and open your browser (builds first if missing)"
	@echo "  make site-down  stop the local site preview container"
	@echo "  make version V=1.2.3  raise the dashboard's version, as a pull request"
	@echo "  make publish    publish the release that main names, after that pull request is merged"

dev:
	./dashboard.sh up

uv:
	./dashboard.sh uv

app-start:
	./dashboard.sh app-start

app-bundle:
	./dashboard.sh app-bundle

down:
	./dashboard.sh down

clean:
	./dashboard.sh clean

test:
	./dashboard.sh test

site:
	./site/build.sh

site-show:
	./site/serve.sh up

site-down:
	./site/serve.sh down

version:
	./dashboard.sh version $(V)

publish:
	./dashboard.sh publish

-include meta.mk
