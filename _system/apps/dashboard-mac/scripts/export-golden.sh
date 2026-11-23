#!/usr/bin/env bash
# Writes Tests/Golden/<fixture>/ from what the Go dashboard answers on each
# fixture in Tests/Fixtures/. Run it by hand, then commit the result, in a pull
# request of its own. CI never runs it. Needs Go and Python 3 (standard
# library only) and Node, for the search queries. Two runs give the same files.
set -euo pipefail
command -v node >/dev/null || { echo "export-golden.sh needs Node for the search queries" >&2; exit 1; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(git -C "$here" rev-parse --show-toplevel)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

(cd "$repo/_system/apps/dashboard" && go build -o "$tmp/systems42-dashboard" ./cmd/systems42-dashboard)

python3 -I "$here/scripts/export_golden.py" "$tmp/systems42-dashboard" "$here/Tests/Fixtures" "$tmp/golden"
# The search queries go into the same temp folder, so a failure leaves Tests/Golden as it was.
"$here/scripts/export-search-queries.sh" "$tmp/golden"
# Replace the old files only now that every fixture exported.
rm -rf "$here/Tests/Golden/"*/
mv "$tmp/golden/"* "$here/Tests/Golden/"
find "$here/Tests/Golden" -name .DS_Store -delete
echo "Golden data written to $here/Tests/Golden"
