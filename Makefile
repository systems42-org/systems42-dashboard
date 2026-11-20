# Thin wrapper around dashboard.sh, the launcher: `make dev` instead of
# `./dashboard.sh up`. `./dashboard.sh logs|update` have no target here; call
# the script directly.
#
# `make test`, `make version` and `make publish` work only in the dashboard's own repository,
# which holds the dashboard code (`./dashboard.sh rebuild|local|test|version|publish`,
# see _system/apps/dashboard/dev.sh).

.DEFAULT_GOAL := help

.PHONY: help dev uv down clean test version publish

help::
	@echo "make dev      start the dashboard release this wiki names (Docker), opens your browser"
	@echo "make uv       start the same release with uv instead of Docker; Ctrl+C stops it"
	@echo "make down     stop the dashboard"
	@echo "make clean    remove what can be rebuilt (container, caches); never content"
	@echo "make test     run the dashboard's test scripts (Docker; dashboard repository only)"
	@echo "make version V=1.2.3  raise the dashboard's version, as a pull request (dashboard repository only)"
	@echo "make publish  publish the release that main names, after that pull request is merged"

dev:
	./dashboard.sh up

uv:
	./dashboard.sh uv

down:
	./dashboard.sh down

clean:
	./dashboard.sh clean

test:
	./dashboard.sh test

version:
	./dashboard.sh version $(V)

publish:
	./dashboard.sh publish

-include meta.mk
