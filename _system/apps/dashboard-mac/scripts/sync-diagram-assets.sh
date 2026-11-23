#!/usr/bin/env bash
# Copies the diagram libraries and graph styles the web dashboard ships into
# Sources/Systems42UI/Resources/diagram/, and pins their checksums in CHECKSUMS.
# Run it by hand, then commit the result. `--check` changes nothing: it compares the
# committed copies with _system/apps/dashboard/static/ and exits 1 on any difference.
# The Swift tests read only CHECKSUMS, never the dashboard.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(git -C "$here" rev-parse --show-toplevel)"
static="$repo/_system/apps/dashboard/static"
out="$here/Sources/Systems42UI/Resources/diagram"

# source (below static/) | file name here
files=(
  "vendor/mermaid.min.js|mermaid.min.js"
  "vendor/cytoscape.min.js|cytoscape.min.js"
  "vendor/layout-base.js|layout-base.js"
  "vendor/cose-base.js|cose-base.js"
  "vendor/cytoscape-fcose.js|cytoscape-fcose.js"
  "glossary-graph.js|glossary-graph.js"
  "metamodel-graph.js|metamodel-graph.js"
)

if [ "${1:-}" = "--check" ]; then
  bad=0
  for entry in "${files[@]}"; do
    src="$static/${entry%%|*}"; dst="$out/${entry##*|}"
    if [ ! -f "$dst" ]; then echo "missing: ${entry##*|}"; bad=1
    elif ! cmp -s "$src" "$dst"; then echo "differs from the dashboard: ${entry##*|}"; bad=1; fi
  done
  sums="$(cd "$out" && for entry in "${files[@]}"; do shasum -a 256 "${entry##*|}"; done)"
  if [ "$sums" != "$(cat "$out/CHECKSUMS" 2>/dev/null || true)" ]; then echo "CHECKSUMS does not match the copies"; bad=1; fi
  if [ "$bad" -ne 0 ]; then echo "Diagram assets differ. Run scripts/sync-diagram-assets.sh and commit." >&2; exit 1; fi
  echo "Diagram assets match the dashboard."
  exit 0
fi

mkdir -p "$out"
for entry in "${files[@]}"; do cp "$static/${entry%%|*}" "$out/${entry##*|}"; done
(cd "$out" && for entry in "${files[@]}"; do shasum -a 256 "${entry##*|}"; done) > "$out/CHECKSUMS"
# Last commit that changed a source, so later unrelated commits leave SOURCE alone.
git -C "$repo" log -1 --format=%H -- _system/apps/dashboard/static > "$out/SOURCE"
echo "Diagram assets written to $out from $(cat "$out/SOURCE")"
