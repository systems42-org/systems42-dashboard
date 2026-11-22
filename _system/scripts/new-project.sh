#!/usr/bin/env bash
#
# Create a fresh Systems42 requirements wiki from this one, or refresh the
# method files of an existing one — without ever copying project content
# (DR-031, resolving ISS-006).
#
#   _system/scripts/new-project.sh new     <target-dir> --name "<System>" [--tagline "<one line>"] [--no-git]
#   _system/scripts/new-project.sh sync    <target-dir> [--force]
#   _system/scripts/new-project.sh harvest <target-dir> [--out <patch-file>]
#   _system/scripts/new-project.sh migrate-decisions <target-dir>
#   _system/scripts/new-project.sh migrate-requirements <target-dir>
#   _system/scripts/new-project.sh migrate-domain-terms <target-dir>
#
# `new`  copies the PRODUCT paths (schema, templates, anchors, workflows,
#        skills, dashboard, docs) into an empty <target-dir>, resets the
#        project files (wiki/, raw/, wiki.yaml, index.md, log.md), and makes
#        an initial git commit.
# `sync` re-copies the product paths into an existing project so that method
#        fixes made here flow forward. It never touches wiki/, raw/, wiki.yaml,
#        index.md or log.md (decision records are wiki content, so they never
#        travel either way), and keeps skills and docs the project added.
#        It overwrites (and, in the mirrored folders, deletes) the project's
#        product files, so it refuses when a file it would change has
#        uncommitted changes or is ignored by git (inside a submodule too), or
#        when it would change any file in a project that is not a git
#        repository — that work could not be got back. If one of these checks
#        cannot be completed, it stops rather than guess.
#        Commit it (or `harvest` it first), or pass --force to overwrite anyway.
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
# `migrate-requirements` upgrades a project spawned before functional
#        requirements carried `notation:` + `level:` (DR-038): `stereotype:`
#        becomes `notation: agile` + `level:`, and wiki/use-cases/ pages move
#        into wiki/functional-requirements/ in use-case notation, IDs kept.
#        Uncommitted, for review. `sync` refuses a project that still needs it.
#
# Run it from the project you want to copy FROM: every Systems42 instance
# carries this script, so a customised wiki can spawn another in its image.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$HERE/../.." && pwd)"

# --- the product allow-list ---------------------------------------------------
# Single files, copied as-is. _system/notations/ itself belongs to the project
# (its own requirement notations, FR-023): only the README there is product,
# so the folder is neither mirrored, merged nor harvested.
PRODUCT_FILES=(AGENTS.md CLAUDE.md README.md CHANGELOG.md Makefile dashboard.sh .gitignore _system/README.md
               _system/notations/README.md)
# Directories owned entirely by the product: mirrored, stale files removed on sync.
PRODUCT_DIRS_MIRROR=(_templates _system/anchors _system/metamodel _system/workflows _system/scripts raw/examples)
# Directories the product ships but a project may add to: merged, nothing removed.
# .obsidian carries the vault settings the guide relies on (excluded files, themes);
# workspace.json is gitignored and never travels. Skills live in .agents/skills;
# .claude/skills holds one symlink per skill for Claude Code (DR-037).
PRODUCT_DIRS_MERGE=(docs .agents/skills .claude/skills .obsidian)
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
  # A project from before DR-037 has real skill folders in .claude/skills where
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

# --- what a sync would change -------------------------------------------------
# sync's safety check needs the files copy_product would create, overwrite or
# delete. It compares contents itself instead of reading rsync's dry-run
# output: that output differs between GNU rsync and Apple's openrsync (macOS
# reports deletions without the itemize column and lists unchanged single
# files as transfers), and a guard that misreads it either deletes unprotected
# work or blocks a sync that would change nothing.

# True when <path> (relative to a copied folder) matches RSYNC_EXCLUDES —
# such files are neither copied nor deleted. Keep the two lists together.
is_excluded() {  # is_excluded <path relative to the copied folder>
  local rel="$1" part n i=0 IFS=/
  case "$rel" in superpowers/*) return 0 ;; esac          # '/superpowers/' (anchored)
  set -f; set -- $rel; set +f
  n=$#
  for part; do
    i=$((i + 1))
    case "$part" in .DS_Store|workspace.json|workspace-mobile.json|*.pyc) return 0 ;; esac
    if [ "$i" -lt "$n" ]; then                             # folder patterns: '.venv/' …
      case "$part" in .venv|__pycache__|.pytest_cache) return 0 ;; esac
    fi
  done
  return 1
}

# Files and symlinks below <dir>, relative to it, without excluded ones.
list_files() {  # list_files <dir>
  local f
  # prune the excluded folders instead of walking them (a local .venv holds
  # thousands of files); is_excluded still has the final word on every path
  (cd "$1" && find . \( -path ./superpowers -o -name .venv -o -name __pycache__ -o -name .pytest_cache \) \
     -type d -prune -o \( -type f -o -type l \) -print) | sed 's#^\./##' \
    | while IFS= read -r f; do is_excluded "$f" || printf '%s\n' "$f"; done
}

# True when <dst> already is what rsync -a would make of <src>: the same
# symlink target, or a regular file with the same content and the same
# executable bit (rsync -a copies the mode too; git tracks only that bit).
same_entry() {  # same_entry <src> <dst>
  if [ -L "$1" ] || [ -L "$2" ]; then
    [ -L "$1" ] && [ -L "$2" ] && [ "$(readlink "$1")" = "$(readlink "$2")" ]
  else
    [ -f "$2" ] && cmp -s "$1" "$2" || return 1
    if [ -x "$1" ]; then [ -x "$2" ]; else [ ! -x "$2" ]; fi
  fi
}

# What copying the source entry <src> to <target>/<rel> would change, as
# paths relative to <target>. rsync -a puts a real folder at every ancestor
# of <rel>, so a file or symlink sitting at one of them is replaced; a folder
# sitting at <rel> itself is replaced by the file, with everything in it.
entry_changes() {  # entry_changes <src> <target> <rel>
  local src="$1" target="$2" rel="$3" rest="$3" anc="" f
  while [ "${rest#*/}" != "$rest" ]; do
    anc="${anc:+$anc/}${rest%%/*}"
    rest="${rest#*/}"
    if [ -L "$target/$anc" ] || { [ -e "$target/$anc" ] && [ ! -d "$target/$anc" ]; }; then
      printf '%s\n' "$anc"
      return
    fi
  done
  if [ -d "$target/$rel" ] && [ ! -L "$target/$rel" ]; then
    list_files "$target/$rel" | while IFS= read -r f; do printf '%s\n' "$rel/$f"; done
    return
  fi
  same_entry "$src" "$target/$rel" || printf '%s\n' "$rel"
}

# The paths on stdin that are one of the <dirty> paths or lie below one.
# git reports a submodule with uncommitted changes as a single path
# (`docs/req42`), not as the files inside it.
under_dirty() {  # under_dirty <dirty paths, one per line>  < paths
  DIRTY="$1" awk '
    BEGIN { n = split(ENVIRON["DIRTY"], D, "\n"); for (i = 1; i <= n; i++) if (D[i] != "") dirty[D[i]] = 1 }
    $0 != "" {
      p = $0
      while (1) {
        if (p in dirty) { print $0; next }
        if (index(p, "/") == 0) break
        sub(/\/[^\/]*$/, "", p)
      }
    }'
}

# The paths on stdin (relative to <repo>) that git ignores in <repo>, printed
# with <prefix> in front. Exit 2 when git cannot answer.
check_ignored_in() {  # check_ignored_in <repo> <prefix>  < paths
  local out rc=0 f
  out="$(git -C "$1" -c core.quotePath=false check-ignore --stdin)" || rc=$?
  [ "$rc" -le 1 ] || return 2                  # 0: some ignored, 1: none, else: failed
  [ -z "$out" ] || printf '%s\n' "$out" | while IFS= read -r f; do printf '%s%s\n' "$2" "$f"; done
}

# Those of <path>s (relative to <target>, one per line on stdin) that exist
# in <target> and that git ignores there: `git status` never shows them, and
# git could not bring them back after sync overwrote or deleted them. A path
# inside a submodule is asked of that submodule's repository (the outer one
# refuses to answer for it). Exit 2 when a check cannot be completed.
ignored_existing() {  # ignored_existing <target>  < paths
  local target="$1" f s existing subs pairs
  existing="$(while IFS= read -r f; do
                if [ -n "$f" ] && { [ -e "$target/$f" ] || [ -L "$target/$f" ]; }; then printf '%s\n' "$f"; fi
              done)"
  [ -n "$existing" ] || return 0
  # registered submodules (gitlinks, mode 160000), relative to <target>
  subs="$(git -C "$target" -c core.quotePath=false ls-files --stage -- . \
          | awk -F'\t' '{ split($1, m, " ") } m[1] == "160000" { print $2 }')" || return 2
  # "<submodule>\t<path inside it>", or "\t<path>" outside any submodule
  pairs="$(printf '%s\n' "$existing" | SUBS="$subs" awk '
    BEGIN { n = split(ENVIRON["SUBS"], S, "\n") }
    {
      best = ""
      for (i = 1; i <= n; i++)
        if (S[i] != "" && index($0, S[i] "/") == 1 && length(S[i]) > length(best)) best = S[i]
      print best "\t" (best == "" ? $0 : substr($0, length(best) + 2))
    }')"
  while IFS= read -r s; do
    printf '%s\n' "$pairs" | awk -F'\t' -v s="$s" '$1 == s { print $2 }' \
      | check_ignored_in "$target${s:+/$s}" "${s:+$s/}" || return 2
  done <<EOF
$(printf '%s\n' "$pairs" | cut -f1 | LC_ALL=C sort -u)
EOF
}

# Every file `sync` would create, overwrite or delete in <target>, one per
# line, relative to <target> (duplicates possible). Follows copy_product
# step by step.
changed_paths() {  # changed_paths <target>
  local target="$1" p f s name
  for p in "${PRODUCT_FILES[@]}"; do
    [ -e "$SRC_ROOT/$p" ] || continue
    entry_changes "$SRC_ROOT/$p" "$target" "$p"
  done
  for p in "${PRODUCT_DIRS_MIRROR[@]}" "${PRODUCT_DIRS_MERGE[@]}"; do
    [ -d "$SRC_ROOT/$p" ] || continue
    list_files "$SRC_ROOT/$p" | while IFS= read -r f; do
      entry_changes "$SRC_ROOT/$p/$f" "$target" "$p/$f"
    done
  done
  for p in "${PRODUCT_DIRS_MIRROR[@]}"; do                 # --delete: what the source lacks
    [ -d "$SRC_ROOT/$p" ] && [ -d "$target/$p" ] || continue
    list_files "$target/$p" | while IFS= read -r f; do
      [ -e "$SRC_ROOT/$p/$f" ] || [ -L "$SRC_ROOT/$p/$f" ] || printf '%s\n' "$p/$f"
    done
  done
  for s in "$SRC_ROOT"/.claude/skills/*; do                # real skill folders become links
    [ -L "$s" ] || continue
    name="$(basename "$s")"
    f="$target/.claude/skills/$name"
    if [ -d "$f" ] && [ ! -L "$f" ]; then
      list_files "$f" | sed "s#^#.claude/skills/$name/#"
    fi
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

## Domain terms

## Goals

## Stakeholders

## Context

## External interfaces

## Activity models

## Functional requirements

## Quality requirements

## Constraints

## Building blocks

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
  local target="$1" name="$2" tagline="$3" version
  # The new project runs the dashboard release this repository runs.
  version="$(sed -n 's/^dashboard_version:[[:space:]]*"\{0,1\}\([^"#[:space:]]*\).*/\1/p' "$SRC_ROOT/_system/wiki.yaml" | head -n 1)"
  cat > "$target/_system/wiki.yaml" <<EOF
# Project identity for this requirements wiki.
#
# The dashboard reads this file live; edit it and refresh the browser.
system_name: "$name"  # the system whose requirements this vault holds
tagline: "$tagline"  # one line, shown under the name in the dashboard hero
# about: docs/<folder>/README.md  # optional: a page under docs/ shown at /about (hero mark + link)
# about_label: ""                  # optional: link text and page title; empty → "About <system_name>"
# default_notation: agile          # optional: notation for new functional requirements (FR-004); empty → agile
# brand: brand/                    # optional: a folder with this wiki's marks, favicon and intro; empty → systems42
dashboard_version: "$version"  # the dashboard release this wiki runs; `./dashboard.sh update` names the newest
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

# Paths of <target> with uncommitted changes (modified, staged, deleted or
# untracked), one per line, relative to <target>; empty when clean. Exit 2
# when <target> is not inside a git work tree, so "clean" and "unknown" differ.
dirty_paths() {  # dirty_paths <target>
  local target="$1" prefix rec skip=0
  git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 2
  prefix="$(git -C "$target" rev-parse --show-prefix)"   # target may sit below the repo root
  # --ignore-submodules=none overrides `submodule.<name>.ignore` and
  # `diff.ignoreSubmodules`, which would otherwise hide edits inside a submodule
  git -C "$target" status --porcelain -z --untracked-files=all --ignore-submodules=none -- . \
    | while IFS= read -r -d '' rec; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi          # a rename's old path: gone anyway
    case "$rec" in R*|C*) skip=1 ;; esac
    rec="${rec:3}"
    printf '%s\n' "${rec#"$prefix"}"
  done
}

cmd_sync() {  # sync <target-dir> [--force]
  local target="${1:-}" force=0
  [ -n "$target" ] || die "sync: missing <target-dir>"
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --force) force=1; shift ;;
      *) die "sync: unknown option $1" ;;
    esac
  done
  [ -f "$target/_system/wiki.yaml" ] || die "sync: $target is not a Systems42 project (no _system/wiki.yaml)"
  target="$(cd "$target" && pwd)"
  [ "$target" != "$SRC_ROOT" ] || die "sync: target is this project"
  if [ -d "$target/_system/adr" ]; then
    die "sync: $target still keeps decisions in _system/adr/, which the synced dashboard no longer reads.
Migrate them first:  $0 migrate-decisions \"$target\"   (then review, commit, and sync again)"
  fi
  local legacy
  if ! legacy="$(python3 "$HERE/migrate-requirements.py" --check "$target")"; then
    die "sync: $target still has functional requirements or use cases in the pre-notation format,
which the synced dashboard and lint no longer read:
$legacy
Migrate them first:  $0 migrate-requirements \"$target\"   (then review, commit, and sync again)"
  fi

  if ! legacy="$(python3 "$HERE/migrate-domain-terms.py" --check "$target")"; then
    die "sync: $target still has legacy glossary or data-model content:
$legacy
Migrate it first:  $0 migrate-domain-terms \"$target\"   (then review, commit, and sync again)"
  fi

  # sync overwrites the project's copies of the product files and deletes
  # stale ones in the mirrored folders. Method edits made there and not yet
  # committed would be gone for good, so stop unless told otherwise — but only
  # for files this sync would really change: a project's own docs, skills or
  # excluded folders (docs/superpowers/) are never touched and never block.
  # Files git ignores count as uncommitted: git status hides them, and git
  # could not restore them either.
  if [ "$force" -eq 0 ]; then
    local touched dirty at_risk rc=0
    touched="$(changed_paths "$target" | LC_ALL=C sort -u)" \
      || die "sync: could not work out which files sync would change in $target"
    dirty="$(dirty_paths "$target")" || rc=$?
    if [ "$rc" -eq 2 ]; then
      if [ -n "$touched" ]; then
        die "sync: $target is not a git repository, and sync would overwrite or delete $(printf '%s\n' "$touched" | wc -l | tr -d ' ') file(s) there
that could not be restored afterwards:
$(printf '%s\n' "$touched" | head -20 | sed 's/^/  /')
Put the project under git and commit first, or run again with --force to overwrite anyway."
      fi
    elif [ "$rc" -ne 0 ]; then
      die "sync: git status failed in $target (exit $rc)"
    else
      local ignored
      ignored="$(printf '%s\n' "$touched" | ignored_existing "$target")" \
        || die "sync: could not check which files in $target git ignores, so sync cannot tell what it would destroy.
Run again with --force to sync anyway."
      at_risk="$({ printf '%s\n' "$touched" | under_dirty "$dirty"; printf '%s\n' "$ignored"; } \
                 | sed '/^$/d' | LC_ALL=C sort -u)"
      if [ -n "$at_risk" ]; then
        die "sync: $target has uncommitted (or git-ignored) files sync would overwrite or delete:
$(printf '%s\n' "$at_risk" | sed 's/^/  /')
Commit them there first (method changes worth keeping: run \`$0 harvest \"$target\"\` before syncing),
or run again with --force to overwrite them."
      fi
    fi
  fi

  echo "Syncing product files from $SRC_ROOT into $target"
  copy_product "$target" mirror
  ensure_type_folders "$target"
  echo
  echo "Done. Review with: git -C \"$target\" status"
}

ensure_type_folders() {  # <target>: every content type's wiki folder exists (a new type added since)
  local f folder
  for f in "$1"/_system/metamodel/types/type-*.md; do
    folder="$(sed -n 's/^folder: *//p' "$f" | head -1)"
    [ -n "$folder" ] && [ ! -d "$1/$folder" ] || continue
    mkdir -p "$1/$folder" && touch "$1/$folder/.gitkeep"
    echo "  created $folder/ (new content type)"
  done
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
  [ -d "$(dirname "$out")" ] || die "harvest: directory for --out does not exist: $(dirname "$out")"

  # Stage the product paths of both sides in a scratch dir — `a` this repository,
  # `b` the project — with the same excludes `new` and `sync` use, then let git
  # diff them, so the patch carries a/ and b/ prefixes and `git apply` (-p1)
  # applies it here. rsync and git both keep a symlink a symlink: the
  # .claude/skills links (DR-037) show up as links, never as a second copy of
  # the skill they point to, which `git apply` would refuse.
  local work; work="$(mktemp -d)"
  # set -e can stop the script anywhere below (a failing rsync); the scratch
  # copy of both sides must not be left behind in $TMPDIR when it does.
  trap "rm -rf '$work'" EXIT
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
      rsync -a "${RSYNC_EXCLUDES[@]}" "$src/$p/" "$work/$side/$p/"
    done
  done
  # Diff into the scratch dir first: `git diff` exits 1 for "there are
  # differences", which a failed redirect into an unwritable $out would also
  # return, and a half-written patch must never look like a finished one.
  rc=0
  (cd "$work" && git diff --no-index --no-prefix --binary --no-renames --no-color \
                  --no-ext-diff --no-textconv a b > "$work/harvest.patch") || rc=$?
  [ "$rc" -le 1 ] || die "harvest: git diff failed (exit $rc)"
  cp "$work/harvest.patch" "$out" || die "harvest: cannot write $out"
  rm -rf "$work"
  trap - EXIT
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

cmd_migrate_requirements() {  # migrate-requirements <target-dir>
  local target="${1:-}"
  [ -n "$target" ] || die "migrate-requirements: missing <target-dir>"
  [ -f "$target/_system/wiki.yaml" ] || die "migrate-requirements: $target is not a Systems42 project (no _system/wiki.yaml)"
  target="$(cd "$target" && pwd)"
  [ "$target" != "$SRC_ROOT" ] || die "migrate-requirements: target is this project"
  command -v python3 >/dev/null || die "migrate-requirements: python3 is required"
  python3 "$HERE/migrate-requirements.py" "$target"
  echo
  echo "Review with: git -C \"$target\" status   — then commit there and run sync."
}

cmd_migrate_domain_terms() {
  local target="${1:-}"
  [ -n "$target" ] || die "migrate-domain-terms: missing <target-dir>"
  [ -f "$target/_system/wiki.yaml" ] || die "migrate-domain-terms: target is not a Systems42 project"
  target="$(cd "$target" && pwd)"
  [ "$target" != "$SRC_ROOT" ] || die "migrate-domain-terms: target is this project"
  python3 "$HERE/migrate-domain-terms.py" "$target"
}

case "${1:-}" in
  new)     shift; cmd_new "$@" ;;
  sync)    shift; cmd_sync "$@" ;;
  harvest) shift; cmd_harvest "$@" ;;
  migrate-decisions) shift; cmd_migrate_decisions "$@" ;;
  migrate-requirements) shift; cmd_migrate_requirements "$@" ;;
  migrate-domain-terms) shift; cmd_migrate_domain_terms "$@" ;;
  -h|--help|"") usage ;;
  *) die "unknown command: $1 (expected new|sync|harvest|migrate-decisions|migrate-requirements|migrate-domain-terms)" ;;
esac
