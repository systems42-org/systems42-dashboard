#!/usr/bin/env bash
#
# Smoke test for new-project.sh (DR-031). Plain bash asserts, no runner.
#
#   _system/scripts/test-new-project.sh
#
# Creates a fresh project in a temp dir, checks that only the product shipped
# (no wiki pages, no raw sources, no project identity), then plants project
# content, syncs, and checks the project content survived while method files
# were refreshed.
#
set -uo pipefail   # no -e: a failing [ ] must reach check(), not abort the run

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$HERE/new-project.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/new-project-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TARGET="$TMP/foo-shop"

failures=0
check() {  # check <condition-exit-code> <message>
  if [ "$1" -eq 0 ]; then echo "  ok   $2"; else echo "  FAIL $2"; failures=$((failures + 1)); fi
}
# Portable "directory holds nothing but .gitkeep".
only_gitkeep() { [ -z "$(find "$1" -mindepth 1 ! -name .gitkeep -print -quit)" ]; }

echo "== new"
"$SCRIPT" new "$TARGET" --name "Foo Shop" --tagline "Buy foo, fast." >"$TMP/new.out" 2>&1 \
  || { cat "$TMP/new.out"; echo "new-project.sh new failed"; exit 1; }

# product shipped
for p in AGENTS.md CLAUDE.md README.md CHANGELOG.md Makefile dashboard.sh .gitignore _system/README.md \
         _templates/goal.md _system/anchors/req42.md _system/workflows/bootstrap.md \
         _system/workflows/capture.md _system/apps/dashboard/app.py \
         _system/scripts/new-project.sh .agents/skills/capture/SKILL.md \
         .agents/skills/grill-requirements/SKILL.md .agents/skills/new-project/SKILL.md \
         .claude/skills/capture/SKILL.md .claude/skills/grill-requirements/SKILL.md docs/GETTING-STARTED.md docs/req42/README.md \
         .obsidian/app.json; do
  [ -e "$TARGET/$p" ]; check $? "ships $p"
done
cmp -s "$SRC_ROOT/AGENTS.md" "$TARGET/AGENTS.md"; check $? "AGENTS.md is byte-identical to the source"
cmp -s "$SRC_ROOT/CLAUDE.md" "$TARGET/CLAUDE.md"; check $? "CLAUDE.md is byte-identical to the source"
# Skills live once in .agents/skills; Claude Code reaches each through a link.
for s in "$SRC_ROOT"/.agents/skills/*/; do
  s="$(basename "$s")"
  [ -L "$TARGET/.claude/skills/$s" ] && [ "$(readlink "$TARGET/.claude/skills/$s")" = "../../.agents/skills/$s" ]
  check $? ".claude/skills/$s is a link to .agents/skills/$s"
done
[ -x "$TARGET/dashboard.sh" ]; check $? "dashboard.sh stays executable"
[ ! -e "$TARGET/_system/adr" ]; check $? "no _system/adr/ (decisions are wiki content, DR-034)"
[ -d "$TARGET/wiki/decisions" ] && only_gitkeep "$TARGET/wiki/decisions"; check $? "wiki/decisions exists and is empty"
[ -e "$TARGET/_templates/decision-record.md" ]; check $? "ships the decision-record template"
[ -e "$TARGET/_system/anchors/madr.md" ]; check $? "ships the MADR anchor"
# Shipped Markdown states its rules in place and links no decision of this
# repository (DR-034): a [[DR- link would dangle or hit the project's own DR.
[ -z "$(grep -rlE '\[\[(DR-[0-9]{3}|ADR-[0-9]{4}|00[0-9]{2}-)' --include='*.md' "$TARGET" --exclude-dir=wiki --exclude-dir=.git --exclude=decision-record.md)" ]
check $? "no shipped Markdown links a decision record"

# project content NOT shipped
[ ! -e "$TARGET/docs/superpowers" ]; check $? "docs/superpowers (meta's own dev specs) not shipped"
[ ! -e "$TARGET/.obsidian/workspace.json" ]; check $? "Obsidian workspace state not shipped"
[ ! -e "$TARGET/_system/apps/dashboard/.venv" ]; check $? "dashboard .venv not shipped"
[ -z "$(find "$TARGET" -name __pycache__ -print -quit)" ]; check $? "no __pycache__ shipped"
for d in $(cd "$SRC_ROOT/wiki" && ls -d */); do
  d="${d%/}"
  [ -d "$TARGET/wiki/$d" ] && only_gitkeep "$TARGET/wiki/$d"; check $? "wiki/$d exists and is empty"
done
[ -d "$TARGET/raw/ingested" ] && only_gitkeep "$TARGET/raw/ingested"; check $? "raw/ingested exists and is empty"
[ -d "$TARGET/raw/sources" ]  && only_gitkeep "$TARGET/raw/sources";  check $? "raw/sources exists and is empty"
[ -d "$TARGET/raw/assets" ]   && only_gitkeep "$TARGET/raw/assets";   check $? "raw/assets exists and is empty"
[ -z "$(find "$TARGET/raw" -maxdepth 1 -type f ! -name .gitkeep -print -quit)" ]; check $? "raw/ inbox is empty"
[ -z "$(grep -rl -E '\[\[(GOAL|STK|GLO|SRC|ISS|FR|QR|CON|CTX|EIF|DM|AM|UC|DR)-[0-9]{3}' "$TARGET/_system/index.md" "$TARGET/_system/log.md" 2>/dev/null)" ]
check $? "index/log carry no page links from the source project"

# project identity reset
grep -q '^system_name: "Foo Shop"' "$TARGET/_system/wiki.yaml"; check $? "wiki.yaml names the new system"
grep -q '^tagline: "Buy foo, fast."' "$TARGET/_system/wiki.yaml"; check $? "wiki.yaml carries the tagline"
! grep -q 'Systems42' "$TARGET/_system/wiki.yaml"; check $? "wiki.yaml no longer says Systems42"
[ -f "$TARGET/_system/dashboard.yaml" ]; check $? "dashboard.yaml created on new"
grep -q '^hidden: \[\]' "$TARGET/_system/dashboard.yaml"; check $? "dashboard.yaml starts with nothing hidden"
grep -q '"AGENTS.md"' "$TARGET/.obsidian/app.json"; check $? "Obsidian excludes AGENTS.md from the vault graph"
for h in Glossary Goals Stakeholders Context "External interfaces" "Data models" "Activity models" \
         "Use cases" "Functional requirements" "Quality requirements" Constraints Decisions Issues Sources; do
  grep -q "^## $h\$" "$TARGET/_system/index.md"; check $? "index.md has heading '$h'"
done
! grep -q '^- \[' "$TARGET/_system/index.md"; check $? "index.md lists no entries"
grep -q 'No decision records are inherited' "$TARGET/_system/log.md"; check $? "log.md states that no decisions are inherited"
! grep -q 'Architecture Decisions\|_system/adr' "$TARGET/_system/index.md" "$TARGET/_system/log.md"; check $? "index/log no longer mention ADRs"
grep -q '^## \[[0-9-]*\] new-project | Foo Shop' "$TARGET/_system/log.md"; check $? "log.md has the creation entry"
[ "$(grep -c '^## \[' "$TARGET/_system/log.md")" -eq 1 ]; check $? "log.md has exactly one entry"

# git
[ -d "$TARGET/.git" ]; check $? "git repository initialised"
[ "$(git -C "$TARGET" rev-list --count HEAD)" -eq 1 ]; check $? "exactly one initial commit"
[ -z "$(git -C "$TARGET" status --porcelain)" ]; check $? "working tree clean after initial commit"

echo "== new refuses a non-empty target"
! "$SCRIPT" new "$TARGET" --name "Again" >/dev/null 2>&1; check $? "refuses to overwrite an existing project"

echo "== sync"
mkdir -p "$TARGET/wiki/goals"
echo "planted" > "$TARGET/wiki/goals/GOAL-001-foo.md"
echo "project-specific edit" >> "$TARGET/CLAUDE.md"
echo "project-specific edit" >> "$TARGET/AGENTS.md"
# a project from before the shared skill layout: a real skill folder where a link now belongs
rm "$TARGET/.claude/skills/capture" && mkdir -p "$TARGET/.claude/skills/capture" \
  && echo "old copy" > "$TARGET/.claude/skills/capture/SKILL.md"
mkdir -p "$TARGET/wiki/decisions"
printf -- '---\nid: DR-001\ntitle: "Own decision"\n---\n' > "$TARGET/wiki/decisions/DR-001-own-decision.md"
mkdir -p "$TARGET/.claude/skills/own-skill" && echo "mine" > "$TARGET/.claude/skills/own-skill/SKILL.md"
mkdir -p "$TARGET/.agents/skills/own-agent-skill" && echo "mine" > "$TARGET/.agents/skills/own-agent-skill/SKILL.md"
cp "$TARGET/_system/wiki.yaml" "$TMP/wiki.yaml.before"
cp "$TARGET/_system/log.md" "$TMP/log.md.before"
printf 'hidden: [C6]\n' > "$TARGET/_system/dashboard.yaml"
"$SCRIPT" sync "$TARGET" >"$TMP/sync.out" 2>&1 || { cat "$TMP/sync.out"; echo "sync failed"; exit 1; }

[ "$(cat "$TARGET/wiki/goals/GOAL-001-foo.md")" = "planted" ]; check $? "sync keeps wiki pages"
cmp -s "$SRC_ROOT/CLAUDE.md" "$TARGET/CLAUDE.md"; check $? "sync refreshes CLAUDE.md from the source"
cmp -s "$SRC_ROOT/AGENTS.md" "$TARGET/AGENTS.md"; check $? "sync refreshes AGENTS.md from the source"
[ -L "$TARGET/.claude/skills/capture" ]; check $? "sync turns an old real skill folder into the link"
cmp -s "$TMP/wiki.yaml.before" "$TARGET/_system/wiki.yaml"; check $? "sync leaves wiki.yaml alone"
cmp -s "$TMP/log.md.before" "$TARGET/_system/log.md"; check $? "sync leaves log.md alone"
grep -q '^hidden: \[C6\]' "$TARGET/_system/dashboard.yaml"; check $? "sync leaves dashboard.yaml alone"
[ -e "$TARGET/wiki/decisions/DR-001-own-decision.md" ]; check $? "sync keeps the project's own decision records"
[ ! -e "$TARGET/wiki/decisions/DR-034-decisions-as-madr-records-in-the-wiki.md" ]; check $? "sync ships no decision record of this repository"
[ -e "$TARGET/.claude/skills/own-skill/SKILL.md" ]; check $? "sync keeps the project's own skills"
[ -e "$TARGET/.agents/skills/own-agent-skill/SKILL.md" ]; check $? "sync keeps the project's own .agents skills"
[ ! -e "$TARGET/docs/superpowers" ]; check $? "sync still excludes docs/superpowers"

echo "== harvest"
tmpl="$(ls "$TARGET/_templates"/*.md | head -1)"
echo "# harvested tweak" >> "$tmpl"
mkdir -p "$TARGET/wiki/new-test-type" && touch "$TARGET/wiki/new-test-type/.gitkeep"
printf -- '---\nid: DR-002\ntitle: "Runtime scenarios as a content type"\n---\n' > "$TARGET/wiki/decisions/DR-002-runtime-scenarios.md"
echo "identity: changed" >> "$TARGET/_system/wiki.yaml"
echo "content" > "$TARGET/wiki/goals/GOAL-002-bar.md"
# skills: an edit to a shipped skill, and a new skill with its Claude link
echo "# harvested skill tweak" >> "$TARGET/.agents/skills/capture/SKILL.md"
mkdir -p "$TARGET/.agents/skills/new-skill"
printf -- '---\nname: new-skill\ndescription: A skill the project wrote.\n---\n' > "$TARGET/.agents/skills/new-skill/SKILL.md"
ln -s ../../.agents/skills/new-skill "$TARGET/.claude/skills/new-skill"
# junk the excludes must keep out
echo junk > "$TARGET/.agents/skills/.DS_Store"
mkdir -p "$TARGET/docs/superpowers" && echo "dev notes" > "$TARGET/docs/superpowers/notes.md"
"$SCRIPT" harvest "$TARGET" --out "$TMP/h.patch" >"$TMP/harvest.out" 2>&1 || { cat "$TMP/harvest.out"; echo "harvest failed"; exit 1; }
grep -q '^+# harvested tweak' "$TMP/h.patch"; check $? "patch carries the template edit"
grep -q "^+++ b/_templates/$(basename "$tmpl")" "$TMP/h.patch"; check $? "patch paths carry a/ b/ prefixes"
grep -q '^+++ b/.claude/skills/own-skill/SKILL.md' "$TMP/h.patch"; check $? "patch carries a skill the project added"
grep -q '^+++ b/.agents/skills/own-agent-skill/SKILL.md' "$TMP/h.patch"; check $? "patch carries an .agents skill the project added"
grep -q '^--- /dev/null' "$TMP/h.patch"; check $? "added files use /dev/null so git apply creates them"
! grep -q 'wiki.yaml\|GOAL-002\|identity: changed' "$TMP/h.patch"; check $? "patch excludes identity files and wiki content"
! grep -q '1970-01-01' "$TMP/h.patch"; check $? "no epoch timestamps left in the patch"
[ "$(grep -c '^+# harvested skill tweak' "$TMP/h.patch")" -eq 1 ]; check $? "a skill edit appears once in the patch"
grep -q '^+++ b/.agents/skills/capture/SKILL.md' "$TMP/h.patch"; check $? "the skill edit comes through its canonical .agents path"
! grep -q '\.claude/skills/capture' "$TMP/h.patch"; check $? "nothing comes through the skill's .claude link"
grep -q '^+++ b/.agents/skills/new-skill/SKILL.md' "$TMP/h.patch"; check $? "patch adds a new skill under .agents"
grep -A1 '^diff --git .*/\.claude/skills/new-skill$' "$TMP/h.patch" | grep -q '^new file mode 120000'
check $? "patch adds the new skill's .claude link as a symlink"
grep -q '^+\.\./\.\./\.agents/skills/new-skill$' "$TMP/h.patch"; check $? "the new link points at ../../.agents/skills/new-skill"
! grep -q 'DS_Store\|superpowers' "$TMP/h.patch"; check $? "patch honours the shipping excludes (.DS_Store, docs/superpowers)"
git -C "$SRC_ROOT" apply --check "$TMP/h.patch"; check $? "patch applies here (git apply --check)"
APPLIED="$TMP/applied"
rsync -a --exclude .git --exclude .venv --exclude __pycache__ "$SRC_ROOT/" "$APPLIED/"
(cd "$APPLIED" && git apply "$TMP/h.patch"); check $? "patch applies to a copy of this repository"
[ -L "$APPLIED/.claude/skills/new-skill" ] && [ -f "$APPLIED/.claude/skills/new-skill/SKILL.md" ]
check $? "applied, .claude/skills/new-skill is a link that reaches the new skill"
grep -q '^# harvested skill tweak' "$APPLIED/.agents/skills/capture/SKILL.md" && [ -L "$APPLIED/.claude/skills/capture" ]
check $? "applied, the skill edit lands in .agents and the .claude link stays a link"
grep -q 'wiki/new-test-type/' "$TMP/harvest.out"; check $? "reports the project's new wiki folder"
grep -q 'DR-002-runtime-scenarios — Runtime scenarios as a content type' "$TMP/harvest.out"; check $? "lists the project's decision records with their titles"
! grep -q 'DR-001-record-architecture-decisions' "$TMP/harvest.out"; check $? "does not list this repository's decision records"
grep -q 'as DR-[0-9][0-9][0-9] onward' "$TMP/harvest.out"; check $? "names the next free DR number here"
! grep -q 'decisions/DR-' "$TMP/h.patch"; check $? "patch carries no decision record"
"$SCRIPT" harvest "$TARGET" >"$TMP/harvest2.out" 2>&1; check $? "harvest without --out succeeds"
ls "$SRC_ROOT"/harvest-foo-shop-[0-9]*.patch >/dev/null 2>&1; check $? "default patch lands in the source root, named after the project (no yaml comment in the name)"
rm -f "$SRC_ROOT"/harvest-foo-shop-*.patch
grep -q '^harvest-\*\.patch$' "$SRC_ROOT/.gitignore"; check $? ".gitignore keeps harvest patches out of git"

echo "== legacy project: decisions still in _system/adr/"
LEGACY="$TMP/legacy"
"$SCRIPT" new "$LEGACY" --name "Legacy" --no-git >/dev/null 2>&1 || { echo "new (legacy) failed"; exit 1; }
mkdir -p "$LEGACY/_system/adr"
printf '# ADR-NNNN: <Title>\n' > "$LEGACY/_system/adr/0000-template.md"
printf '# ADR-0001: Record architecture decisions\n\n- **Status:** accepted\n- **Date:** 2026-05-23\n\n## Context\nx\n\n## Decision\ny\n\n## Consequences\nz\n' \
  > "$LEGACY/_system/adr/0001-record-architecture-decisions.md"
printf '# ADR-0004: Use **Postgres** for orders\n\n- **Status:** accepted\n- **Date:** 2026-09-01\n\n## Context\nOrders need storage; supersedes nothing, see ADR-0001.\n\n## Decision\nWe use Postgres.\n\n## Consequences\nOps must run it.\n\n## Alternatives considered\n1. SQLite\n2. Flat files keyed by `\\d+` order numbers\n' \
  > "$LEGACY/_system/adr/0004-use-postgres-for-orders.md"
printf '# ADR-0005: Keep orders in memory\n\n- **Status:** superseded by ADR-0004\n- **Date:** 2026-08-01\n\n## Context\nx\n\n## Decision\ny\n\n## Consequences\nz\n' \
  > "$LEGACY/_system/adr/0005-keep-orders-in-memory.md"
printf -- '---\nid: CON-001\ntitle: x\n---\nSee [[0004-use-postgres-for-orders|ADR-0004]] and [[0001-record-architecture-decisions|ADR-0001]].\n' \
  > "$LEGACY/wiki/constraints/CON-001-x.md"
printf '# Index\n\n## Constraints\n\n## Issues\n\n## Sources\n\n## Architecture Decisions (ADR)\n\n- [0000-template](adr/0000-template.md) — ADR-0000, the Nygard template\n- [0004-use-postgres-for-orders](adr/0004-use-postgres-for-orders.md) — ADR-0004, Use Postgres\n' \
  > "$LEGACY/_system/index.md"
! "$SCRIPT" sync "$LEGACY" >"$TMP/legacy-sync.out" 2>&1; check $? "sync refuses a project that still has _system/adr/"
grep -q 'migrate-decisions' "$TMP/legacy-sync.out"; check $? "the refusal names the migrate-decisions command"
[ -d "$LEGACY/_system/adr" ]; check $? "the refused sync left _system/adr/ alone"
"$SCRIPT" migrate-decisions "$LEGACY" >"$TMP/migrate.out" 2>&1; check $? "migrate-decisions succeeds"
dr="$LEGACY/wiki/decisions/DR-004-use-postgres-for-orders.md"
[ -f "$dr" ]; check $? "the project's own ADR-0004 became DR-004"
grep -q '^aliases: \[ADR-0004\]' "$dr" && grep -q '^kind: undefined' "$dr"; check $? "DR-004 keeps its former ID as an alias, kind left for the project"
grep -q '^## Considered Options' "$dr" && grep -q 'SQLite' "$dr" && grep -q '^### Consequences' "$dr"; check $? "DR-004 has the MADR sections, options from 'Alternatives considered'"
grep -q '^title: "Use Postgres for orders"' "$dr"; check $? "DR-004 title is plain text"
grep -qF 'keyed by `\d+` order numbers' "$dr"; check $? "backslashes in options survive verbatim"
dr5="$LEGACY/wiki/decisions/DR-005-keep-orders-in-memory.md"
grep -q '^status: deprecated' "$dr5" && grep -q '^superseded-by: \["\[\[DR-004-use-postgres-for-orders\]\]"\]' "$dr5"; check $? "a superseded ADR keeps its successor (superseded-by)"
[ -z "$(ls "$LEGACY/wiki/decisions" | grep -v -e '^DR-004-' -e '^DR-005-' -e '^\.gitkeep$')" ]; check $? "inherited ADR-0000..0003 were not migrated"
[ ! -e "$LEGACY/_system/adr" ]; check $? "_system/adr/ removed"
grep -q '\[\[DR-004-use-postgres-for-orders|DR-004\]\]' "$LEGACY/wiki/constraints/CON-001-x.md"; check $? "wiki links to the ADR now point at DR-004"
! grep -q '\[\[0001-' "$LEGACY/wiki/constraints/CON-001-x.md"; check $? "links to inherited ADRs became plain text"
grep -q '^## Decisions' "$LEGACY/_system/index.md" && grep -q 'DR-004-use-postgres-for-orders.md' "$LEGACY/_system/index.md"; check $? "index lists DR-004 under Decisions"
! grep -q 'Architecture Decisions' "$LEGACY/_system/index.md"; check $? "index lost its ADR section"
"$SCRIPT" sync "$LEGACY" >/dev/null 2>&1; check $? "sync succeeds after the migration"

echo "== harvest refuses a non-project directory"
mkdir -p "$TMP/not-a-project"
! "$SCRIPT" harvest "$TMP/not-a-project" >/dev/null 2>&1; check $? "harvest refuses a directory without _system/wiki.yaml"

echo "== sync refuses a non-project directory"
mkdir -p "$TMP/not-a-project"
! "$SCRIPT" sync "$TMP/not-a-project" >/dev/null 2>&1; check $? "refuses a directory without _system/wiki.yaml"

echo
if [ "$failures" -eq 0 ]; then echo "all checks passed"; else echo "$failures check(s) failed"; exit 1; fi
