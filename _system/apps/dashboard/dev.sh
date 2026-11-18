#!/usr/bin/env bash
#
# Commands for working on the dashboard itself. Only the dashboard's own
# repository has this file. The launcher (dashboard.sh in the repository
# root) hands every command it does not know to this script, so these work:
#
#   ./dashboard.sh rebuild  build the local image from scratch, then start
#   ./dashboard.sh local    run Flask directly, without Docker, on port 8000
#   ./dashboard.sh test     run the test scripts in Docker
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LOCAL_URL="http://localhost:8000"

case "${1:-}" in
  rebuild)
    # Needs `dashboard_version: local` in _system/wiki.yaml to be started.
    docker build --no-cache -t systems42-dashboard:local "$HERE"
    exec "$ROOT/dashboard.sh" up
    ;;
  local)
    # A fallback for machines where Docker will not start, without any promise
    # that it works (CON-003).
    cd "$HERE"
    if [ ! -d .venv ]; then
      echo "→ First run: building the virtualenv and installing requirements (~20 s)…"
      python3 -m venv .venv
      .venv/bin/pip install -q --disable-pip-version-check -r requirements.txt
    fi
    export REPO_DIR="$ROOT"
    .venv/bin/python -c 'import preflight; preflight.stop_if_not_a_systems42_wiki()'
    .venv/bin/python app.py &
    server_pid=$!
    tries=60
    while [ "$tries" -gt 0 ] && ! curl -sf --max-time 1 -o /dev/null "$LOCAL_URL/"; do
      tries=$((tries - 1)); sleep 0.5
    done
    echo "✓ Dashboard (local, no Docker) on $LOCAL_URL"
    if [ -z "${DASH_NO_BROWSER:-}" ]; then
      if command -v open >/dev/null 2>&1; then open "$LOCAL_URL"
      elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$LOCAL_URL"
      fi
    fi
    wait "$server_pid" || true
    ;;
  test)
    # The test stage of the Dockerfile: the shipped image's Python and
    # libraries, plus make and node, which some scripts call. The repository
    # is mounted read-only and copied inside the container, so the tests run
    # against the code as it is here and cannot change a file on the host
    # (one script touches a metamodel file).
    docker build -q --target test -t systems42-dashboard-test "$HERE" >/dev/null
    docker run --rm -v "$ROOT:/repo:ro" systems42-dashboard-test sh -c '
      mkdir /work &&
      tar -C /repo --exclude=./.git --exclude=.venv --exclude=__pycache__ -cf - . | tar -C /work -xf - &&
      sh /work/_system/apps/dashboard/tests/run-all.sh'
    ;;
  *)
    echo "Unknown command: ${1:-}" >&2
    echo "Usage: ./dashboard.sh [up|down|logs|update|clean|rebuild|local|test]" >&2
    exit 2
    ;;
esac
