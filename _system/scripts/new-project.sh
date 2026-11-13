#!/usr/bin/env bash
#
# Create a fresh Systems42 requirements wiki from this one, or refresh the
# method files of an existing one — without ever copying project content
# (DR-031, resolving ISS-006).
#
#   _system/scripts/new-project.sh new     <target-dir> --name "<System>" [--tagline "<one line>"] [--no-git]
#   _system/scripts/new-project.sh sync    <target-dir>
#   _system/scripts/new-project.sh harvest <target-dir> [--out <patch-file>]
#   _system/scripts/new-project.sh migrate-decisions <target-dir>
#
# `new`  copies the PRODUCT paths (schema, templates, anchors, workflows,
#        skills, dashboard, docs) into an empty <target-dir>, resets the
#        project files (wiki/, raw/, wiki.yaml, index.md, log.md), and makes
#        an initial git commit.
# `sync` re-copies the product paths into an existing project so that method
#        fixes made here flow forward. It never touches wiki/, raw/, wiki.yaml,
#        index.md or log.md (decision records are wiki content, so they never
#        travel either way), and keeps skills and docs the project added.
# `harvest` is the way BACK: it diffs the product paths of a project against
#        this repository and writes a patch you review and `git apply` here,
#        then lists the project's new wiki/ folders (new content types need
#        their folder here) and its own decision records (a method decision
#        among them gets re-recorded here as a DR under the next free number).
#        It writes nothing but the patch.
# `migrate-decisions` upgrades a project spawned before decisions became wiki
#        content: its own ADRs in _system/adr/ become wiki/decisions/DR-NNN
#        (same number), the inherited Systems42 ADRs are dropped, links and the
#        index follow, _system/adr/ goes. Uncommitted, for review. `sync`
#        refuses a project that still has _system/adr/.
#
# Run it from the project you want to copy FROM: every Systems42 instance
# carries this script, so a customised wiki can spawn another in its image.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$HERE/../.." && pwd)"

# --- the product allow-list ---------------------------------------------------
# Single files, copied as-is.
PRODUCT_FILES=(AGENTS.md CLAUDE.md README.md CHANGELOG.md Makefile dashboard.sh .gitignore _system/README.md _system/writing-style.md)
# Directories owned entirely by the product: mirrored, stale files removed on sync.
PRODUCT_DIRS_MIRROR=(_templates _system/anchors _system/metamodel _system/workflows _system/scripts _system/apps raw/examples)
# Directories the product ships but a project may add to: merged, nothing removed.
# .obsidian carries the vault settings the guide relies on (excluded files, themes);
# workspace.json is gitignored and never travels. Skills live in .agents/skills;
# .claude/skills holds one symlink per skill for Claude Code.
PRODUCT_DIRS_MERGE=(docs .agents/skills .claude/skills .obsidian _system/notations)
# Decision records are wiki content (wiki/decisions/, DR-034): a new project
# inherits none and starts at DR-001; the product states its rules in place.
DR_DIR=wiki/decisions
# Never shipped. Patterns are relative to each rsync'd directory, so the
# anchored '/superpowers/' hits docs/superpowers (this repo's own dev specs and
# plans) and nothing else.
RSYNC_EXCLUDES=(--exclude '/superpowers/' --exclude '.venv/' --exclude '__pycache__/'
                --exclude '*.pyc' --exclude '.pytest_cache/' --exclude '.DS_Store'
                --exclude 'workspace.json' --exclude 'workspace-mobile.json')

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
die()   { echo "new-project.sh: $*" >&2; exit 1; }

copy_product() {  # copy_product <target> <mirror|merge-only>
  local target="$1" mode="$2" p
  for p in "${PRODUCT_FILES[@]}"; do
    mkdir -p "$target/$(dirname "$p")"
    rsync -a "$SRC_ROOT/$p" "$target/$p"
  done
  for p in "${PRODUCT_DIRS_MIRROR[@]}"; do
    [ -d "$SRC_ROOT/$p" ] || continue
    mkdir -p "$target/$p"
    if [ "$mode" = mirror ]; then
      rsync -a --delete "${RSYNC_EXCLUDES[@]}" "$SRC_ROOT/$p/" "$target/$p/"
    else
      rsync -a "${RSYNC_EXCLUDES[@]}" "$SRC_ROOT/$p/" "$target/$p/"
    fi
  done
  # A project from before the shared skill layout has real skill folders in .claude/skills where
  # the product now ships links; rsync cannot turn a folder into a link, so the
  # product's own copies go first. Skills the project added stay untouched.
  local s
  for s in "$SRC_ROOT"/.claude/skills/*; do
    [ -L "$s" ] || continue
    s="$target/.claude/skills/$(basename "$s")"
    if [ -d "$s" ] && [ ! -L "$s" ]; then rm -rf "$s"; fi
  done
  for p in "${PRODUCT_DIRS_MERGE[@]}"; do
    [ -d "$SRC_ROOT/$p" ] || continue
    mkdir -p "$target/$p"
    rsync -a "${RSYNC_EXCLUDES[@]}" "$SRC_ROOT/$p/" "$target/$p/"
  done
}

dr_title() {  # frontmatter "title:" of a decision record, unquoted
  sed -n 's/^title: *//p' "$1" | head -1 | sed -E 's/^"(.*)"$/\1/'
}

write_index() {  # write_index <target>
  local target="$1"
  {
    cat <<'EOF'
# Index

Content catalog, one line per page, grouped by type. The agent updates this on
every capture (`_system/workflows/capture.md`, step 7).

## Glossary

## Goals

## Stakeholders

## Context

## External interfaces

## Data models

## Activity models

## Use cases

## Functional requirements

## Quality requirements

## Constraints

## Decisions

## Issues

## Sources
EOF
  } > "$target/_system/index.md"
}

write_log() {  # write_log <target> <name> <source-ref>
  local target="$1" name="$2" ref="$3"
  cat > "$target/_system/log.md" <<EOF
# Log

Append-only. One entry per operation. Keep the prefix exact so the log is
greppable: \`grep '^## \[' _system/log.md | tail -5\`.

<!-- Format (indented so the grep above does not match it):
    ## [YYYY-MM-DD] <op> | <subject>
    - Source / scope, grill gate, created, updated, issues, open questions
-->

## [$(date +%Y-%m-%d)] new-project | $name
- Created with \`_system/scripts/new-project.sh new\` from $ref.
- Product paths copied (schema, templates, anchors, workflows, skills, dashboard, docs). No decision records are inherited: \`wiki/decisions/\` starts empty and this project's own decisions start at DR-001.
- \`wiki/\` and \`raw/\` start empty. Next step: \`_system/workflows/bootstrap.md\`.
EOF
}

write_wiki_yaml() {  # write_wiki_yaml <target> <name> <tagline>
  local target="$1" name="$2" tagline="$3"
  cat > "$target/_system/wiki.yaml" <<EOF
# Project identity for this requirements wiki.
#
# The dashboard reads this file live; edit it and refresh the browser.
system_name: "$name"  # the system whose requirements this vault holds
tagline: "$tagline"  # one line, shown under the name in the dashboard hero
# about: docs/<folder>/README.md  # optional: a page under docs/ shown at /about (hero mark + link)
# about_label: ""                  # optional: link text and page title; empty → "About <system_name>"
# Dashboard look. All three keys are optional.
# brand: systems42  # an example brand (systems42, atrium) or a folder in this repository, e.g. brand/; missing → systems42
# intro: on  # off: the home page opens without the brand's intro animation
# dashboard_version: ""  # the dashboard release this wiki uses; the footer notes a different one
EOF
}

write_dashboard_yaml() {  # write_dashboard_yaml <target>
  cat > "$1/_system/dashboard.yaml" <<'EOF'
# Dashboard settings — written by the dashboard's Configure dialog (facilitator
# only); hand-editable too. Everything is visible unless listed here.
# `hidden` takes area keys (requirements | architecture | commons) and/or
# section IDs (R1-R6, A1-A5, C1-C7) from the Systems42 sections diagram.
hidden: []
EOF
}

cmd_new() {
  local target="" name="" tagline="" do_git=1
  while [ $# -gt 0 ]; do
    case "$1" in
      --name)    name="${2:-}"; shift 2 ;;
      --tagline) tagline="${2:-}"; shift 2 ;;
      --no-git)  do_git=0; shift ;;
      -h|--help) usage ;;
      -*)        die "unknown option: $1" ;;
      *)         [ -z "$target" ] || die "unexpected argument: $1"; target="$1"; shift ;;
    esac
  done
  [ -n "$target" ] || die "new: missing <target-dir>"
  [ -n "$name" ]   || die "new: --name is required (the system whose requirements the new wiki holds)"
  if [ -e "$target" ] && [ -n "$(ls -A "$target" 2>/dev/null)" ]; then
    die "new: $target exists and is not empty — use 'sync' to refresh an existing project"
  fi
  mkdir -p "$target"
  target="$(cd "$target" && pwd)"

  echo "Creating $name in $target"
  copy_product "$target" mirror

  local d
  for d in "$SRC_ROOT"/wiki/*/; do
    mkdir -p "$target/wiki/$(basename "$d")"; touch "$target/wiki/$(basename "$d")/.gitkeep"
  done
  for d in raw raw/ingested raw/sources raw/assets; do
    mkdir -p "$target/$d"; touch "$target/$d/.gitkeep"
  done

  local ref="$SRC_ROOT"
  if git -C "$SRC_ROOT" rev-parse --short HEAD >/dev/null 2>&1; then
    ref="$(basename "$SRC_ROOT") @ $(git -C "$SRC_ROOT" rev-parse --short HEAD)"
  fi
  write_wiki_yaml "$target" "$name" "$tagline"
  write_dashboard_yaml "$target"
  write_index "$target"
  write_log "$target" "$name" "$ref"

  if [ "$do_git" -eq 1 ]; then
    if [ ! -d "$target/.git" ]; then git -C "$target" init -q; fi
    git -C "$target" add -A
    git -C "$target" -c user.name="${GIT_AUTHOR_NAME:-new-project.sh}" \
                     -c user.email="${GIT_AUTHOR_EMAIL:-new-project@localhost}" \
                     commit -q -m "Create $name requirements wiki from Systems42 ($ref)"
  fi

  cat <<EOF

Done. Next:
  1. cd "$target"
  2. open it in Obsidian and start Claude Code there
  3. tell the agent: "Run the bootstrap workflow"
EOF
}

cmd_sync() {
  local target="${1:-}"
  [ -n "$target" ] || die "sync: missing <target-dir>"
  [ -f "$target/_system/wiki.yaml" ] || die "sync: $target is not a Systems42 project (no _system/wiki.yaml)"
  target="$(cd "$target" && pwd)"
  [ "$target" != "$SRC_ROOT" ] || die "sync: target is this project"
  if [ -d "$target/_system/adr" ]; then
    die "sync: $target still keeps decisions in _system/adr/, which the synced dashboard no longer reads.
Migrate them first:  $0 migrate-decisions \"$target\"   (then review, commit, and sync again)"
  fi

  echo "Syncing product files from $SRC_ROOT into $target"
  copy_product "$target" mirror
  echo
  echo "Done. Review with: git -C \"$target\" status"
}

cmd_harvest() {  # harvest <target-dir> [--out <patch-file>]
  local target="${1:-}" out=""
  [ -n "$target" ] || die "harvest: missing <target-dir>"
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --out) out="${2:-}"; [ -n "$out" ] || die "harvest: --out needs a path"; shift 2 ;;
      *) die "harvest: unknown option $1" ;;
    esac
  done
  [ -f "$target/_system/wiki.yaml" ] || die "harvest: $target is not a Systems42 project (no _system/wiki.yaml)"
  target="$(cd "$target" && pwd)"
  [ "$target" != "$SRC_ROOT" ] || die "harvest: target is this project"

  local slug
  slug="$(sed -n 's/^system_name: *//p' "$target/_system/wiki.yaml" | head -1 | sed 's/#.*//' | tr -d '"' \
          | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')"
  [ -n "$slug" ] || slug="$(basename "$target")"
  [ -n "$out" ] || out="$SRC_ROOT/harvest-$slug-$(date +%Y%m%d).patch"
  case "$out" in /*) ;; *) out="$PWD/$out" ;; esac

  # Stage the product paths of both sides in a scratch dir — `a` this repository,
  # `b` the project — with the same excludes `new` and `sync` use, then let git
  # diff them, so the patch carries a/ and b/ prefixes and `git apply` (-p1)
  # applies it here. rsync and git both keep a symlink a symlink: the
  # .claude/skills links show up as links, never as a second copy of
  # the skill they point to, which `git apply` would refuse.
  local work; work="$(mktemp -d)"
  local side src p rc
  for side in a b; do
    if [ "$side" = a ]; then src="$SRC_ROOT"; else src="$target"; fi
    for p in "${PRODUCT_FILES[@]}"; do
      [ -e "$src/$p" ] || continue
      mkdir -p "$work/$side/$(dirname "$p")"
      rsync -a "$src/$p" "$work/$side/$p"
    done
    for p in "${PRODUCT_DIRS_MIRROR[@]}" "${PRODUCT_DIRS_MERGE[@]}"; do
      [ -d "$src/$p" ] || continue
      mkdir -p "$work/$side/$p"
      if [ "$p" = "_system/notations" ]; then
        # Project-specific notation definitions are local configuration. Keep
        # only the product README in harvest patches; never harvest custom files.
        rsync -a --include='/README.md' --exclude='*' "$src/$p/" "$work/$side/$p/"
      else
        rsync -a "${RSYNC_EXCLUDES[@]}" "$src/$p/" "$work/$side/$p/"
      fi
    done
  done
  rc=0
  (cd "$work" && git diff --no-index --no-prefix --binary --no-renames --no-color \
                  --no-ext-diff --no-textconv a b > "$out") || rc=$?
  rm -rf "$work"
  [ "$rc" -le 1 ] || die "harvest: git diff failed (exit $rc)"
  local n_files; n_files="$(grep -c '^diff --git ' "$out" || true)"

  # New content types need their wiki/ folder here, or the next `new` lacks it.
  local d n folders=()
  for d in "$target"/wiki/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    [ -d "$SRC_ROOT/wiki/$n" ] || folders+=("$n")
  done

  # The project's own decision records: a method decision among them gets
  # re-recorded here as a DR; decisions about the project's system stay there.
  local f id drs=() next=0
  for f in "$SRC_ROOT/$DR_DIR"/DR-*.md; do
    [ -e "$f" ] || continue
    id="$(basename "$f" | cut -c4-6)"
    [ "$((10#$id))" -gt "$next" ] && next="$((10#$id))"
  done
  next="$((next + 1))"
  for f in "$target/$DR_DIR"/DR-*.md; do
    [ -e "$f" ] || continue
    drs+=("$(basename "$f" .md) — $(dr_title "$f")")
  done

  echo "Harvesting method changes from $target into $SRC_ROOT"
  echo
  if [ "$n_files" -gt 0 ]; then
    echo "Patch: $out ($n_files file(s) differ on the product paths)"
    echo "  review it, then apply here:  git apply --3way \"$out\""
    echo "  (dry run first:              git apply --check \"$out\")"
  else
    rm -f "$out"
    echo "No differences on the product paths — nothing to patch."
  fi
  if [ "${#folders[@]}" -gt 0 ]; then
    echo
    echo "wiki/ folders the project has and this repository lacks (new content types?):"
    for n in "${folders[@]}"; do
      echo "  wiki/$n/   →  mkdir -p wiki/$n && touch wiki/$n/.gitkeep   (plus its _templates/ file, AGENTS.md row, catalog entry)"
    done
  fi
  if [ "${#drs[@]}" -gt 0 ]; then
    echo
    echo "The project's decision records — re-record any method decision here as DR-$(printf '%03d' "$next") onward, citing its origin:"
    printf '  %s\n' "${drs[@]}"
  fi
  echo
  echo "After applying: record the decision behind a schema change, open a PR (AGENTS.md commit policy), then"
  echo "  $0 sync \"$target\"   # so the project matches again"
}

cmd_migrate_decisions() {  # migrate-decisions <target-dir>
  local target="${1:-}"
  [ -n "$target" ] || die "migrate-decisions: missing <target-dir>"
  [ -f "$target/_system/wiki.yaml" ] || die "migrate-decisions: $target is not a Systems42 project (no _system/wiki.yaml)"
  target="$(cd "$target" && pwd)"
  [ "$target" != "$SRC_ROOT" ] || die "migrate-decisions: target is this project"
  command -v python3 >/dev/null || die "migrate-decisions: python3 is required"
  python3 "$HERE/migrate-decisions.py" "$target"
  echo
  echo "Review with: git -C \"$target\" status   — then commit there and run sync."
}

case "${1:-}" in
  new)     shift; cmd_new "$@" ;;
  sync)    shift; cmd_sync "$@" ;;
  harvest) shift; cmd_harvest "$@" ;;
  migrate-decisions) shift; cmd_migrate_decisions "$@" ;;
  -h|--help|"") usage ;;
  *) die "unknown command: $1 (expected new|sync|harvest|migrate-decisions)" ;;
esac
