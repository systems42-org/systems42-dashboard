#!/usr/bin/env bash
# Manages the local Docker preview server for site/_site/.
# Zero local Python required.
#
# Usage:
#   ./site/serve.sh [up|down]
#   make site-show
#   make site-down
#   SITE_PORT=8091 make site-show
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
OUT="${SITE_OUT:-$HERE/_site}"
PORT="${SITE_PORT:-8090}"
URL="http://localhost:${PORT}"
IMAGE="systems42-dashboard-site"
CONTAINER="systems42-dashboard-site-preview"
CMD="${1:-up}"

case "$CMD" in
  down)
    if docker ps -aq -f "name=^/${CONTAINER}$" | grep -q .; then
      docker rm -f "$CONTAINER" >/dev/null
      echo "✓ Stopped site preview server ($CONTAINER)"
    else
      echo "Site preview server is not running."
    fi
    ;;

  up)
    if [ ! -f "$OUT/index.html" ]; then
      "$HERE/build.sh"
    fi

    # Ensure the lightweight base image exists (cached after `make site`).
    docker build -q --target base -t "$IMAGE" "$ROOT/_system/apps/dashboard" >/dev/null

    # Replace any previous preview container cleanly.
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

    docker run -d --rm --init --name "$CONTAINER" \
      -p "127.0.0.1:${PORT}:8090" \
      -v "$OUT:/site:ro" \
      "$IMAGE" \
      python -m http.server 8090 --bind 0.0.0.0 --directory /site >/dev/null

    tries=40
    while :; do
      docker ps -q -f "name=^/${CONTAINER}$" | grep -q . || {
        echo "✗ Could not start the site preview container (is port ${PORT} busy?)." >&2
        exit 1
      }
      if command -v curl >/dev/null 2>&1; then
        curl -sf --max-time 1 -o /dev/null "${URL}/" && break
      else
        sleep 1
        break
      fi
      tries=$((tries - 1))
      if [ "$tries" -le 0 ]; then
        echo "… preview server did not answer yet; open ${URL} manually." >&2
        break
      fi
      sleep 0.25
    done

    echo "✓ Serving dashboard.systems42.org preview at ${URL} (Docker; stop with \`make site-down\`)"

    if [ -z "${SITE_NO_BROWSER:-}" ]; then
      if command -v open >/dev/null 2>&1; then
        open "$URL"
      elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$URL"
      fi
    fi
    ;;

  *)
    echo "Usage: $0 [up|down]" >&2
    exit 2
    ;;
esac
