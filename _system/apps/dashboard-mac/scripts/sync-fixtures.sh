#!/usr/bin/env bash
# Rebuilds Tests/Fixtures/ from the Python dashboard's fixtures and this
# repository's metamodel and anchors. Run it by hand, then commit the result.
# CI never runs it. The same sources always give the same files.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(git -C "$here" rev-parse --show-toplevel)"
src="$repo/_system/apps/dashboard/tests/fixtures"
out="$here/Tests/Fixtures"

if [ -n "$(git -C "$repo" status --porcelain -- _system/metamodel _system/anchors _system/apps/dashboard/tests/fixtures)" ]; then
  echo "Uncommitted changes in the sources. Commit them first." >&2
  exit 1
fi

# name | folder holding the type folders | folder holding wiki.yaml ("" = none)
build() {
  local name="$1" wiki_src="$2" yaml_src="$3" dest="$out/$1"
  mkdir -p "$dest/wiki" "$dest/raw/sources" "$dest/_system"
  cp -R "$src/$wiki_src/." "$dest/wiki/"
  touch "$dest/raw/sources/.gitkeep"
  if [ -n "$yaml_src" ] && [ -f "$src/$yaml_src/wiki.yaml" ]; then
    cp "$src/$yaml_src/wiki.yaml" "$dest/_system/wiki.yaml"
  else
    printf 'system_name: "%s fixture"\n' "$name" > "$dest/_system/wiki.yaml"
  fi
  cp -R "$repo/_system/metamodel" "$dest/_system/metamodel"
  cp -R "$repo/_system/anchors" "$dest/_system/anchors"
}

rm -rf "$out"
mkdir -p "$out"
build basic wiki ""
build search search-wiki ""
build arc42 arc42/wiki ""
build arc42-views arc42-views/wiki ""
build domain-model domain-model/wiki domain-model

find "$out" -name .DS_Store -delete
# Last commit that changed a source, so later unrelated commits leave SOURCE alone.
git -C "$repo" log -1 --format=%H -- _system/metamodel _system/anchors _system/apps/dashboard/tests/fixtures > "$out/SOURCE"
echo "Fixtures written to $out from $(cat "$out/SOURCE")"
