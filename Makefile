# Thin wrapper around dashboard.sh, the launcher: `make dev` instead of
# `./dashboard.sh up`. `./dashboard.sh logs|update` have no target here; call
# the script directly.
#
# `make test` works only in the dashboard's own repository, which holds the
# dashboard code (`./dashboard.sh rebuild|local|test`, see
# _system/apps/dashboard/dev.sh).

.DEFAULT_GOAL := help

.PHONY: help dev down clean test

help::
	@echo "make dev      start the dashboard release this wiki names (Docker), opens your browser"
	@echo "make down     stop the dashboard"
	@echo "make clean    remove what can be rebuilt (container, caches); never content"
	@echo "make test     run the dashboard's test scripts (Docker; dashboard repository only)"

dev:
	./dashboard.sh up

down:
	./dashboard.sh down

clean:
	./dashboard.sh clean

test:
	./dashboard.sh test

-include meta.mk
