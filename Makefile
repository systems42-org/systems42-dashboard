# Thin wrapper around dashboard.sh, the launcher: `make dev` instead of
# `./dashboard.sh up`. `./dashboard.sh logs|update` have no target here; call
# the script directly.
#
# `make test`, `make version` and `make publish` work only in the dashboard's own repository,
# which holds the dashboard code (`./dashboard.sh rebuild|local|test|version|publish`,
# see _system/apps/dashboard/dev.sh).

.DEFAULT_GOAL := help

.PHONY: help dev down clean test site version publish

help::
	@echo "make dev      start the dashboard release this wiki names (Docker), opens your browser"
	@echo "make down     stop the dashboard"
	@echo "make clean    remove what can be rebuilt (container, caches); never content"
	@echo "make test     run the dashboard's test scripts (Docker; dashboard repository only)"
	@echo "make site     build the static dashboard.systems42.org site into site/_site/ (Docker)"
	@echo "make version V=1.2.3  raise the dashboard's version, as a pull request (dashboard repository only)"
	@echo "make publish  publish the release that main names, after that pull request is merged"

dev:
	./dashboard.sh up

down:
	./dashboard.sh down

clean:
	./dashboard.sh clean

test:
	./dashboard.sh test

site:
	./site/build.sh

version:
	./dashboard.sh version $(V)

publish:
	./dashboard.sh publish

-include meta.mk
