# Thin wrapper around dashboard.sh so day-to-day commands read as
# `make dev` / `make down` instead of `./dashboard.sh up` / `./dashboard.sh down`.
# All the actual logic (Docker vs. local fallback, the facilitator link,
# the dashboard's self-shutdown lifecycle) lives in dashboard.sh — this just names the targets.

.DEFAULT_GOAL := help

.PHONY: help dev down rebuild logs local clean new sync harvest migrate-decisions

help:
	@echo "make dev      build + start the dashboard (Docker), opens your browser"
	@echo "make down     stop the dashboard"
	@echo "make rebuild  clean rebuild, then start"
	@echo "make logs     follow the dashboard's container logs"
	@echo "make local    run Flask directly, no Docker (workshop-laptop fallback)"
	@echo "make clean    remove what can be rebuilt (container, image, .venv, caches); never content"
	@echo "make new TARGET=../foo NAME=\"Foo Shop\" [TAGLINE=\"...\"]"
	@echo "              create a fresh wiki beside this one: method files, no content"
	@echo "make sync TARGET=../foo"
	@echo "              refresh the method files in a wiki created with 'make new'"
	@echo "make harvest TARGET=../foo [OUT=file.patch]"
	@echo "              bring method changes made in that wiki back here as a patch to review"
	@echo "make migrate-decisions TARGET=../foo"
	@echo "              move an older wiki's _system/adr/ into wiki/decisions/ (needed before sync)"

# `new` / `sync` wrap _system/scripts/new-project.sh; see that file's header and
# the new-project skill. TARGET is a directory, NAME the system whose
# requirements the new wiki will hold.
new:
	@test -n "$(TARGET)" || { echo "usage: make new TARGET=<dir> NAME=\"<System>\" [TAGLINE=\"<line>\"]"; exit 2; }
	@test -n "$(NAME)"   || { echo "usage: make new TARGET=<dir> NAME=\"<System>\" [TAGLINE=\"<line>\"]"; exit 2; }
	./_system/scripts/new-project.sh new "$(TARGET)" --name "$(NAME)" --tagline "$(TAGLINE)"

sync:
	@test -n "$(TARGET)" || { echo "usage: make sync TARGET=<dir>"; exit 2; }
	./_system/scripts/new-project.sh sync "$(TARGET)"

harvest:
	@test -n "$(TARGET)" || { echo "usage: make harvest TARGET=<dir> [OUT=<patch-file>]"; exit 2; }
	./_system/scripts/new-project.sh harvest "$(TARGET)" $(if $(OUT),--out "$(OUT)",)

dev:
	./dashboard.sh up

down:
	./dashboard.sh down

rebuild:
	./dashboard.sh rebuild

logs:
	./dashboard.sh logs

local:
	./dashboard.sh local

clean:
	./dashboard.sh clean

migrate-decisions:
	@test -n "$(TARGET)" || { echo "usage: make migrate-decisions TARGET=<dir>"; exit 2; }
	./_system/scripts/new-project.sh migrate-decisions "$(TARGET)"
