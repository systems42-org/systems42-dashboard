#!/usr/bin/env bash
# Serves the built static site (site/_site/) inside Docker and opens the browser.
# Builds the site first if site/_site/index.html does not exist yet.
# Zero local Python required. Press Ctrl+C to stop.
#
# Usage:
#   make site-show
#   SITE_PORT=8091 make site-show
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
OUT="${SITE_OUT:-$HERE/_site}"
PORT="${SITE_PORT:-8090}"
URL="http://localhost:${PORT}"
IMAGE="systems42-dashboard-site"
CONTAINER="systems42-dashboard-site-preview"

if [ ! -f "$OUT/index.html" ]; then
  "$HERE/build.sh"
fi

# Ensure the lightweight base image exists (cached after `make site`).
docker build -q --target base -t "$IMAGE" "$ROOT/_system/apps/dashboard" >/dev/null

# Replace any previous preview container cleanly.
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

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

echo "✓ Serving dashboard.systems42.org preview at ${URL} (Docker; Ctrl+C to stop)"

if [ -z "${SITE_NO_BROWSER:-}" ]; then
  if command -v open >/dev/null 2>&1; then
    open "$URL"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$URL"
  fi
fi

# Wait in an interruptible way so Ctrl+C / SIGTERM triggers cleanup immediately.
docker wait "$CONTAINER" >/dev/null &
wait "$!" || true
