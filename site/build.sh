#!/usr/bin/env bash
# Builds the static dashboard.systems42.org site into site/_site/ using Docker.
#
# Usage:
#   site/build.sh
#   DEMO_WIKI=/path/to/isaqb-atrium site/build.sh
#   make site
#   make site DEMO_WIKI=/path/to/isaqb-atrium
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
DEMO_WIKI="${DEMO_WIKI:-$ROOT}"
DEMO_WIKI="$(cd "$DEMO_WIKI" && pwd)"
OUT="${SITE_OUT:-$HERE/_site}"

mkdir -p "$OUT"

if [ -n "${SITE_NO_DOCKER:-}" ]; then
  exec python3 "$HERE/build.py" --repo "$ROOT" --demo-wiki "$DEMO_WIKI" --out "$OUT"
fi

IMAGE="systems42-dashboard-site"
docker build -q --target base -t "$IMAGE" "$ROOT/_system/apps/dashboard" >/dev/null

docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$ROOT:/repo:ro" \
  -v "$DEMO_WIKI:/demo-wiki:ro" \
  -v "$OUT:/out" \
  "$IMAGE" \
  python /repo/site/build.py --repo /repo --demo-wiki /demo-wiki --out /out
