#!/usr/bin/env bash
#
# Commands for working on the dashboard itself. Only the dashboard's own
# repository has this file. The launcher (dashboard.sh in the repository
# root) hands every command it does not know to this script, so these work:
#
#   ./dashboard.sh rebuild  build the local image from scratch, then start
#   ./dashboard.sh local    run Flask directly, without Docker, on port 8000;
#                           Ctrl+C stops it
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
    fresh_venv=0
    if [ ! -d .venv ]; then
      echo "→ First run: building the virtualenv and installing requirements (~20 s)…"
      python3 -m venv .venv
      fresh_venv=1
    fi
    # Install again whenever requirements.txt changed since the last install
    # (an update can add a dependency), not only on the first run — otherwise
    # an existing venv starts the new app without it. The stamp lives inside
    # .venv, so deleting the venv resets it too.
    req_sum="$(cksum < requirements.txt)"
    if [ "$(cat .venv/.requirements.cksum 2>/dev/null)" != "$req_sum" ]; then
      [ "$fresh_venv" = 1 ] || echo "→ requirements.txt changed: updating the virtualenv…"
      .venv/bin/pip install -q --disable-pip-version-check -r requirements.txt
      printf '%s\n' "$req_sum" > .venv/.requirements.cksum
    fi
    export REPO_DIR="$ROOT"
    .venv/bin/python -c 'import preflight; preflight.stop_if_not_a_systems42_wiki()'
    # Something already answering on the port is most likely a dashboard left
    # running by an earlier `local` run. Without this check the readiness poll
    # below would get its answer and report success for a server that never
    # started.
    if command -v curl >/dev/null 2>&1 && curl -s --max-time 1 -o /dev/null "$LOCAL_URL/"; then
      echo "✗ Port 8000 is already in use — another dashboard still running?" >&2
      echo "  Close its browser tabs (it then stops by itself) or stop it: lsof -ti tcp:8000 | xargs kill" >&2
      exit 1
    fi
    .venv/bin/python app.py &
    server_pid=$!
    # A job started with & in a script ignores Ctrl+C, so Ctrl+C would end only
    # this script and leave the server running (kept alive by any open tab).
    # Stop it whenever the script ends, and turn Ctrl+C into such an end.
    trap 'kill "$server_pid" 2>/dev/null || true' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    # Wait until it answers — or stop at once if it died, e.g. because a
    # program that does not speak HTTP holds the port (Flask says why above).
    tries=60
    while :; do
      kill -0 "$server_pid" 2>/dev/null || { echo "✗ The dashboard did not start (see the error above)." >&2; exit 1; }
      command -v curl >/dev/null 2>&1 || break           # nothing to poll with; don't stall
      curl -sf --max-time 1 -o /dev/null "$LOCAL_URL/" && break
      tries=$((tries - 1))
      if [ "$tries" -le 0 ]; then echo "… server did not answer yet; reload if the page fails."; break; fi
      sleep 0.5
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
