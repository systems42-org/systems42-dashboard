#!/usr/bin/env bash
#
# Launcher for the Systems42 dashboard (FR-042). The only dashboard code a
# wiki holds: the dashboard itself comes as a container image.
#
#   ./dashboard.sh          start the release this wiki names, open the browser
#   ./dashboard.sh down     stop and remove the container
#   ./dashboard.sh logs     follow the container's log
#   ./dashboard.sh update   name the newest release in _system/wiki.yaml
#   ./dashboard.sh clean    remove what can be rebuilt: container, caches
#
# The release is `dashboard_version:` in _system/wiki.yaml, e.g. "0.9.0".
# `local` builds the image from _system/apps/dashboard/, which only the
# dashboard's own repository has. That repository adds more commands
# (rebuild, local, test), see _system/apps/dashboard/dev.sh.
#
# DASH_PORT sets the port (8080). DASH_PUBLIC_URL sets the address of the QR
# code. DASH_NO_BROWSER=1 starts without opening a browser.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$ROOT/_system/wiki.yaml"
SETTINGS="$ROOT/_system/dashboard.yaml"
DEV_DIR="$ROOT/_system/apps/dashboard"
IMAGE_REPO="ghcr.io/systems42-org/dashboard"
LATEST_RELEASE="https://api.github.com/repos/systems42-org/systems42-dashboard/releases/latest"
LOCAL_IMAGE="systems42-dashboard:local"
# One container per wiki, so two wikis on one machine do not replace each other.
# The folder name alone is not enough: ~/a/wiki and ~/b/wiki would share it.
# So the name ends in a checksum of the wiki's path (cksum is POSIX).
LEGACY_NAME="systems42-dashboard-$(basename "$ROOT" | tr -c 'A-Za-z0-9_.\n-' '-')"
NAME="$LEGACY_NAME-$(printf '%08x' "$(printf '%s' "$ROOT" | cksum | cut -d ' ' -f 1)")"
PORT="${DASH_PORT:-8080}"
URL="http://localhost:$PORT"

die() { echo "✗ $*" >&2; exit 1; }

# Launchers before the checksum named the container after the folder only.
# A container under that name is this wiki's only if it mounts this wiki:
# another wiki in a folder of the same name may own it.
legacy_is_ours() {
  local src
  src="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/repo"}}{{.Source}}{{end}}{{end}}' "$LEGACY_NAME" 2>/dev/null)" || return 1
  [ -n "$src" ] && { [ "$src" = "$ROOT" ] || [ "$src" = "$(cd "$ROOT" && pwd -P)" ]; }
}

# Remove this wiki's container, and its container under the old name.
remove_container() {
  if legacy_is_ours; then docker rm -f "$LEGACY_NAME" >/dev/null 2>&1 || true; fi
  docker rm -f "$NAME" >/dev/null 2>&1
}

need_docker() {
  command -v docker >/dev/null 2>&1 || die "Docker is not installed or not on PATH."
}

# The release this wiki names: the value of `dashboard_version:`, without quotes.
wiki_version() {
  sed -n 's/^dashboard_version:[[:space:]]*"\{0,1\}\([^"#[:space:]]*\).*/\1/p' "$CONFIG" | head -n 1
}

# The host's LAN address, for the QR code on the home page.
lan_ip() {
  if command -v ipconfig >/dev/null 2>&1; then
    ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true
  elif command -v hostname >/dev/null 2>&1; then
    hostname -I 2>/dev/null | awk '{print $1}' || true
  fi
}

# Up to 30 s until the dashboard answers, so the browser never opens on an error page.
wait_for_dashboard() {
  local tries=60
  command -v curl >/dev/null 2>&1 || return 0
  while [ "$tries" -gt 0 ]; do
    curl -sf --max-time 1 -o /dev/null "$URL/" && return 0
    [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" = "true" ] || return 1
    tries=$((tries - 1))
    sleep 0.5
  done
  return 1
}

cmd="${1:-up}"
[ -f "$CONFIG" ] || die "This is not a Systems42 wiki: _system/wiki.yaml is missing in $ROOT."

case "$cmd" in
  up)
    need_docker
    version="$(wiki_version)"
    [ -n "$version" ] || die "_system/wiki.yaml names no dashboard release. Run ./dashboard.sh update, or set dashboard_version: yourself."
    if [ "$version" = "local" ]; then
      [ -f "$DEV_DIR/Dockerfile" ] || die "dashboard_version: local needs the dashboard code in _system/apps/dashboard/."
      image="$LOCAL_IMAGE"
      docker build -q -t "$image" "$DEV_DIR" >/dev/null
    else
      image="$IMAGE_REPO:$version"
      docker image inspect "$image" >/dev/null 2>&1 || docker pull "$image"
    fi
    # Footer time in the host's zone: containers default to UTC.
    if [ -z "${TZ:-}" ] && [ -L /etc/localtime ]; then
      TZ="$(readlink /etc/localtime | sed 's#.*/zoneinfo/##')"
    fi
    ip="$(lan_ip 2>/dev/null || true)"
    public="${DASH_PUBLIC_URL:-http://${ip:-localhost}:$PORT}"
    remove_container || true
    # One mount: the repository, read-only. The dashboard writes nothing there
    # (FR-046). Releases up to 0.11.4 saved the view in the settings file, so a
    # wiki that still has one gets it mounted writable for them.
    # The container runs as the calling user, not as root.
    settings=""
    if [ -f "$SETTINGS" ]; then settings="$SETTINGS:/repo/_system/dashboard.yaml"; fi
    docker run -d --name "$NAME" -p "$PORT:8000" \
      --user "$(id -u):$(id -g)" \
      -e TZ="${TZ:-UTC}" -e DASH_PUBLIC_URL="$public" \
      -v "$ROOT:/repo:ro" \
      ${settings:+-v "$settings"} \
      "$image" >/dev/null
    if ! wait_for_dashboard; then
      echo "✗ The dashboard did not start. Last log lines:" >&2
      docker logs --tail 25 "$NAME" >&2 || true
      exit 1
    fi
    echo "✓ Dashboard $version running at $URL"
    echo "✓ Others in the room: $public (QR on the home page, /join to project it)"
    if [ -z "${DASH_NO_BROWSER:-}" ]; then
      if command -v open >/dev/null 2>&1; then open "$URL"
      elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$URL"
      fi
    fi
    ;;
  down)
    need_docker
    remove_container || true
    echo "✓ Dashboard stopped."
    ;;
  logs)
    need_docker
    if ! docker inspect "$NAME" >/dev/null 2>&1 && legacy_is_ours; then
      docker logs -f "$LEGACY_NAME"
    else
      docker logs -f "$NAME"
    fi
    ;;
  update)
    command -v curl >/dev/null 2>&1 || die "update needs curl."
    newest="$(curl -fsSL "$LATEST_RELEASE" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' | head -n 1)"
    [ -n "$newest" ] || die "Could not find the newest release at $LATEST_RELEASE."
    current="$(wiki_version)"
    if [ "$current" = "$newest" ]; then
      echo "✓ This wiki already names the newest release, $newest."
      exit 0
    fi
    # The launcher writes this one line, not the dashboard (CON-002).
    line="dashboard_version: \"$newest\"  # the dashboard release this wiki uses, quoted"
    tmp="$(mktemp)"
    if grep -q '^#\{0,1\}[[:space:]]*dashboard_version:' "$CONFIG"; then
      awk -v line="$line" '!done && /^#?[[:space:]]*dashboard_version:/ { print line; done = 1; next } { print }' "$CONFIG" > "$tmp"
    else
      { cat "$CONFIG"; echo "$line"; } > "$tmp"
    fi
    cat "$tmp" > "$CONFIG"
    rm -f "$tmp"
    echo "✓ _system/wiki.yaml now names dashboard $newest (was: ${current:-none}). Start it with ./dashboard.sh."
    ;;
  clean)
    # Only what a start rebuilds. A pulled release image stays: other wikis
    # on this machine may use it. No volumes: the mounts are the content.
    if command -v docker >/dev/null 2>&1 && remove_container; then
      docker rmi "$LOCAL_IMAGE" >/dev/null 2>&1 || true
      echo "✓ Container removed."
    else
      echo "… Docker not reachable: container left in place." >&2
    fi
    rm -rf "$DEV_DIR/.venv"
    # Human-owned content and git's own files are not searched at all.
    (cd "$ROOT" && find . \( -path ./.git -o -path ./raw -o -path ./wiki \
        -o -path ./docs -o -path ./sandbox \) -prune \
        -o \( -type d -name __pycache__ -o -type f -name .DS_Store \) -exec rm -rf {} +)
    echo "✓ Removed caches and .DS_Store. wiki/, raw/ and settings untouched."
    ;;
  *)
    # The dashboard's own repository has more commands.
    if [ -x "$DEV_DIR/dev.sh" ]; then
      exec "$DEV_DIR/dev.sh" "$@"
    fi
    echo "Unknown command: $cmd" >&2
    echo "Usage: ./dashboard.sh [up|down|logs|update|clean]" >&2
    exit 2
    ;;
esac
