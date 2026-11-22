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
         _system/workflows/capture.md \
         _system/scripts/new-project.sh .agents/skills/capture/SKILL.md \
         .agents/skills/grill-requirements/SKILL.md .agents/skills/new-project/SKILL.md \
         .claude/skills/capture/SKILL.md .claude/skills/grill-requirements/SKILL.md docs/GETTING-STARTED.md docs/req42/README.md \
         .obsidian/app.json; do
  [ -e "$TARGET/$p" ]; check $? "ships $p"
done
cmp -s "$SRC_ROOT/AGENTS.md" "$TARGET/AGENTS.md"; check $? "AGENTS.md is byte-identical to the source"
cmp -s "$SRC_ROOT/CLAUDE.md" "$TARGET/CLAUDE.md"; check $? "CLAUDE.md is byte-identical to the source"
# Skills live once in .agents/skills; Claude Code reaches each through a link (DR-037).
for s in "$SRC_ROOT"/.agents/skills/*/; do
  s="$(basename "$s")"
  [ -L "$TARGET/.claude/skills/$s" ] && [ "$(readlink "$TARGET/.claude/skills/$s")" = "../../.agents/skills/$s" ]
  check $? ".claude/skills/$s is a link to .agents/skills/$s"
done
[ -x "$TARGET/dashboard.sh" ]; check $? "dashboard.sh stays executable"
[ ! -e "$TARGET/meta.mk" ]; check $? "no meta.mk (project wikis get no new/sync/harvest targets)"
make -C "$TARGET" help 2>/dev/null | grep -q "make clean" && ! make -C "$TARGET" help 2>/dev/null | grep -q "make sync"
check $? "project 'make help' lists clean, not sync"
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
[ ! -e "$TARGET/_system/apps" ]; check $? "no dashboard code shipped (the launcher pulls a release)"
grep -q '^dashboard_version: "[0-9]' "$TARGET/_system/wiki.yaml"; check $? "wiki.yaml names the dashboard release"
[ -z "$(find "$TARGET" -name __pycache__ -print -quit)" ]; check $? "no __pycache__ shipped"
for d in $(cd "$SRC_ROOT/wiki" && ls -d */); do
  d="${d%/}"
  [ -d "$TARGET/wiki/$d" ] && only_gitkeep "$TARGET/wiki/$d"; check $? "wiki/$d exists and is empty"
done
[ -d "$TARGET/raw/ingested" ] && only_gitkeep "$TARGET/raw/ingested"; check $? "raw/ingested exists and is empty"
[ -d "$TARGET/raw/sources" ]  && only_gitkeep "$TARGET/raw/sources";  check $? "raw/sources exists and is empty"
[ -d "$TARGET/raw/assets" ]   && only_gitkeep "$TARGET/raw/assets";   check $? "raw/assets exists and is empty"
[ -z "$(find "$TARGET/raw" -maxdepth 1 -type f ! -name .gitkeep -print -quit)" ]; check $? "raw/ inbox is empty"
[ "$(ls -A "$TARGET/_system/notations")" = "README.md" ]; check $? "_system/notations ships only its README"
[ -z "$(grep -rl -E '\[\[(GOAL|STK|GLO|SRC|ISS|FR|QR|CON|CTX|EIF|DM|AM|UC|DR)-[0-9]{3}' "$TARGET/_system/index.md" "$TARGET/_system/log.md" 2>/dev/null)" ]
check $? "index/log carry no page links from the source project"

# project identity reset
grep -q '^system_name: "Foo Shop"' "$TARGET/_system/wiki.yaml"; check $? "wiki.yaml names the new system"
grep -q '^tagline: "Buy foo, fast."' "$TARGET/_system/wiki.yaml"; check $? "wiki.yaml carries the tagline"
! grep -q 'Systems42' "$TARGET/_system/wiki.yaml"; check $? "wiki.yaml no longer says Systems42"
[ -f "$TARGET/_system/dashboard.yaml" ]; check $? "dashboard.yaml created on new"
grep -q '^hidden: \[\]' "$TARGET/_system/dashboard.yaml"; check $? "dashboard.yaml starts with nothing hidden"
for h in "Domain terms" Goals Stakeholders Context "External interfaces" "Activity models" \
         "Functional requirements" "Quality requirements" Constraints "Building blocks" Decisions Issues Sources; do
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
# a project from before DR-037: a real skill folder where a link now belongs
rm "$TARGET/.claude/skills/capture" && mkdir -p "$TARGET/.claude/skills/capture" \
  && echo "old copy" > "$TARGET/.claude/skills/capture/SKILL.md"
mkdir -p "$TARGET/wiki/decisions"
printf -- '---\nid: DR-001\ntitle: "Own decision"\n---\n' > "$TARGET/wiki/decisions/DR-001-own-decision.md"
mkdir -p "$TARGET/.claude/skills/own-skill" && echo "mine" > "$TARGET/.claude/skills/own-skill/SKILL.md"
mkdir -p "$TARGET/.agents/skills/own-agent-skill" && echo "mine" > "$TARGET/.agents/skills/own-agent-skill/SKILL.md"
cp "$TARGET/_system/wiki.yaml" "$TMP/wiki.yaml.before"
cp "$TARGET/_system/log.md" "$TMP/log.md.before"
printf 'hidden: [C6]\n' > "$TARGET/_system/dashboard.yaml"
# project-specific notations (FR-023): one new, one shadowing a name the product might ship
echo "mine" > "$TARGET/_system/notations/custom-theme-story.md"
echo "mine" > "$TARGET/_system/notations/agile.md"
# a project from before the arc42 types (DR-040): their folders do not exist yet
rm -rf "$TARGET/wiki/deployment-nodes" "$TARGET/wiki/runtime-scenarios"
# uncommitted edits to product files: sync would destroy them, so it refuses
! "$SCRIPT" sync "$TARGET" >"$TMP/dirty-sync.out" 2>&1; check $? "sync refuses uncommitted changes to product files"
grep -q 'CLAUDE.md' "$TMP/dirty-sync.out" && grep -q -- '--force' "$TMP/dirty-sync.out" && grep -q 'harvest' "$TMP/dirty-sync.out"
check $? "the refusal names the dirty file, --force and harvest"
grep -q 'project-specific edit' "$TARGET/CLAUDE.md"; check $? "the refused sync left the edit alone"
git -C "$TARGET" add -A && git -C "$TARGET" -c user.name=test -c user.email=test@example.invalid \
  commit -q -m "project edits"
"$SCRIPT" sync "$TARGET" >"$TMP/sync.out" 2>&1 || { cat "$TMP/sync.out"; echo "sync failed"; exit 1; }

[ "$(cat "$TARGET/wiki/goals/GOAL-001-foo.md")" = "planted" ]; check $? "sync keeps wiki pages"
[ -e "$TARGET/wiki/deployment-nodes/.gitkeep" ] && [ -e "$TARGET/wiki/runtime-scenarios/.gitkeep" ]
check $? "sync creates the folders of content types added since"
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
[ "$(cat "$TARGET/_system/notations/custom-theme-story.md")" = "mine" ]; check $? "sync keeps the project's own notation"
[ "$(cat "$TARGET/_system/notations/agile.md")" = "mine" ]; check $? "sync never overwrites a project notation file"

# a second sync right after the first changes nothing, so the first one's
# uncommitted result must not block it (openrsync lists unchanged files as transfers)
"$SCRIPT" sync "$TARGET" >"$TMP/sync-again.out" 2>&1; check $? "a second sync with nothing to change is not blocked"
# an uncommitted file only the project has, in a mirrored folder: sync would delete it
echo "mine" > "$TARGET/_templates/local-only.md"
! "$SCRIPT" sync "$TARGET" >"$TMP/sync-delete.out" 2>&1; check $? "sync refuses to delete an uncommitted file in a mirrored folder"
grep -q '_templates/local-only.md' "$TMP/sync-delete.out"; check $? "the refusal names the file it would delete"
[ -f "$TARGET/_templates/local-only.md" ]; check $? "the refused sync left it in place"
rm "$TARGET/_templates/local-only.md"
# Type conflicts, each committed in the project and then edited locally, so
# only the edited path itself shows in `git status`.
commit_t() { git -C "$TARGET" add -A && git -C "$TARGET" -c user.name=test -c user.email=test@example.invalid commit -q -m "$1"; }
# a file where the source has a folder: rsync replaces the file by the folder
rm -rf "$TARGET/docs/req42" && echo "mine" > "$TARGET/docs/req42" && commit_t "req42 as a file"
echo "edited" >> "$TARGET/docs/req42"
! "$SCRIPT" sync "$TARGET" >"$TMP/sync-type1.out" 2>&1; check $? "sync refuses to replace an edited file by a folder"
grep -q '^  docs/req42$' "$TMP/sync-type1.out" && grep -q 'edited' "$TARGET/docs/req42"
check $? "the refusal names that file, which stays in place"
git -C "$TARGET" reset -q --hard HEAD~1
# a folder where the source has a file (merge folder, so no deletion pass covers it)
rm "$TARGET/docs/GETTING-STARTED.md" && mkdir "$TARGET/docs/GETTING-STARTED.md" \
  && echo "mine" > "$TARGET/docs/GETTING-STARTED.md/notes.md" && commit_t "a folder instead"
echo "edited" >> "$TARGET/docs/GETTING-STARTED.md/notes.md"
! "$SCRIPT" sync "$TARGET" >"$TMP/sync-type2.out" 2>&1; check $? "sync refuses to replace a folder holding an edited file by a file"
grep -q '^  docs/GETTING-STARTED.md/notes.md$' "$TMP/sync-type2.out" && grep -q 'edited' "$TARGET/docs/GETTING-STARTED.md/notes.md"
check $? "the refusal names the file inside, which stays in place"
git -C "$TARGET" reset -q --hard HEAD~1
# rsync -a copies the mode as well: an uncommitted chmod would be reset
chmod -x "$TARGET/_system/scripts/metamodel-lint.py"
! "$SCRIPT" sync "$TARGET" >"$TMP/sync-mode.out" 2>&1; check $? "sync refuses to reset an uncommitted executable-bit change"
grep -q '_system/scripts/metamodel-lint.py' "$TMP/sync-mode.out" && [ ! -x "$TARGET/_system/scripts/metamodel-lint.py" ]
check $? "the refusal names the file, whose mode stays as it was"
chmod +x "$TARGET/_system/scripts/metamodel-lint.py"
"$SCRIPT" sync "$TARGET" >/dev/null 2>&1; check $? "sync runs again once the project is back to its committed state"
# an excluded path the source has too: rsync never touches it, so an edit there must not block
plan="$(cd "$SRC_ROOT/docs/superpowers/plans" && ls | head -1)"
mkdir -p "$TARGET/docs/superpowers/plans" && echo "my version" > "$TARGET/docs/superpowers/plans/$plan"
"$SCRIPT" sync "$TARGET" >"$TMP/sync-excl.out" 2>&1; check $? "an edit in an excluded folder does not block sync"
[ "$(cat "$TARGET/docs/superpowers/plans/$plan")" = "my version" ]; check $? "and sync leaves it alone"
rm -rf "$TARGET/docs/superpowers"
# a file git ignores, in a mirrored folder: git status hides it and git could not
# restore it, so sync must not delete it unasked (pattern in .git/info/exclude,
# since .gitignore itself is a product file sync would overwrite)
echo '*.local.md' >> "$TARGET/.git/info/exclude"
echo "mine" > "$TARGET/_templates/notes.local.md"
echo "mine" > "$TARGET/docs/notes.local.md"
! "$SCRIPT" sync "$TARGET" >"$TMP/sync-ignored.out" 2>&1; check $? "sync refuses to delete a git-ignored file in a mirrored folder"
grep -q '^  _templates/notes.local.md$' "$TMP/sync-ignored.out" && ! grep -q 'docs/notes.local.md' "$TMP/sync-ignored.out" \
  && [ -f "$TARGET/_templates/notes.local.md" ]
check $? "the refusal names it (not the ignored file sync would keep), and it stays"
rm "$TARGET/_templates/notes.local.md" "$TARGET/docs/notes.local.md"
# a local virtualenv (excluded and ignored) neither blocks sync nor is touched by it
mkdir -p "$TARGET/_system/scripts/.venv/bin" && echo "venv" > "$TARGET/_system/scripts/.venv/bin/python"
"$SCRIPT" sync "$TARGET" >"$TMP/sync-venv.out" 2>&1; check $? "a local .venv does not block sync"
[ "$(cat "$TARGET/_system/scripts/.venv/bin/python")" = "venv" ]; check $? "and sync leaves it alone"
rm -rf "$TARGET/_system/scripts/.venv"
# uncommitted files sync never touches: the project's own doc, an excluded folder
echo "notes" > "$TARGET/docs/project-notes.md"
mkdir -p "$TARGET/docs/superpowers" && echo "plan" > "$TARGET/docs/superpowers/private-plan.md"
"$SCRIPT" sync "$TARGET" >"$TMP/sync-own.out" 2>&1; check $? "uncommitted files sync would keep do not block it"
[ "$(cat "$TARGET/docs/project-notes.md")" = "notes" ] && [ "$(cat "$TARGET/docs/superpowers/private-plan.md")" = "plan" ]
check $? "and sync keeps them"

echo "== harvest"
tmpl="$(ls "$TARGET/_templates"/*.md | head -1)"
echo "# harvested tweak" >> "$tmpl"
mkdir -p "$TARGET/wiki/risk-registers" && touch "$TARGET/wiki/risk-registers/.gitkeep"
printf -- '---\nid: DR-002\ntitle: "Risk registers as a content type"\n---\n' > "$TARGET/wiki/decisions/DR-002-risk-registers.md"
echo "identity: changed" >> "$TARGET/_system/wiki.yaml"
echo "content" > "$TARGET/wiki/goals/GOAL-002-bar.md"
# skills (DR-037): an edit to a shipped skill, and a new skill with its Claude link
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
grep -q 'wiki/risk-registers/' "$TMP/harvest.out"; check $? "reports the project's new wiki folder"
grep -q 'DR-002-risk-registers — Risk registers as a content type' "$TMP/harvest.out"; check $? "lists the project's decision records with their titles"
! grep -q 'DR-001-record-architecture-decisions' "$TMP/harvest.out"; check $? "does not list this repository's decision records"
grep -q 'as DR-[0-9][0-9][0-9] onward' "$TMP/harvest.out"; check $? "names the next free DR number here"
! grep -q 'decisions/DR-' "$TMP/h.patch"; check $? "patch carries no decision record"
! grep -q '_system/notations/' "$TMP/h.patch"; check $? "patch carries no project notation"
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
"$SCRIPT" sync "$LEGACY" >/dev/null 2>&1; check $? "sync without git succeeds while it would change nothing"
echo "local edit" >> "$LEGACY/CLAUDE.md"
! "$SCRIPT" sync "$LEGACY" >"$TMP/nogit-sync.out" 2>&1; check $? "sync refuses to overwrite files in a project that is not a git repository"
grep -q 'not a git repository' "$TMP/nogit-sync.out" && grep -q 'CLAUDE.md' "$TMP/nogit-sync.out" && grep -q -- '--force' "$TMP/nogit-sync.out"
check $? "the refusal says why, names the file and --force"
grep -q 'local edit' "$LEGACY/CLAUDE.md"; check $? "the refused sync left the file alone"
"$SCRIPT" sync "$LEGACY" --force >/dev/null 2>&1; check $? "sync --force succeeds after the migration"

echo "== legacy project: functional requirements before notation + level"
OLDFR="$TMP/oldfr"
"$SCRIPT" new "$OLDFR" --name "Old FR" --no-git >/dev/null 2>&1 || { echo "new (oldfr) failed"; exit 1; }
printf -- '---\nid: FR-001\ntype: functional-requirement\ntitle: Lending\nstereotype: epic    # epic | feature | story\nparent: []\n---\n\n# Lending\n' \
  > "$OLDFR/wiki/functional-requirements/FR-001-lending.md"
mkdir -p "$OLDFR/wiki/use-cases"
printf -- '---\nid: UC-001\ntype: use-case\ntitle: Find course\ntags: [use-case]\nprimary-actor: "[[STK-001-learner]]"\nlevel: user-goal\npriority: should\n---\n\n# Find course\n' \
  > "$OLDFR/wiki/use-cases/UC-001-find-course.md"
printf -- '---\nid: STK-001\ntitle: Learner\n---\nSee [[wiki/use-cases/UC-001-find-course|Find course]], [[UC-001-find-course]] and [it](../use-cases/UC-001-find-course.md).\n' \
  > "$OLDFR/wiki/stakeholders/STK-001-learner.md"
printf '# Index\n\n## Use cases\n\n- [UC-001](../wiki/use-cases/UC-001-find-course.md) — Find course.\n\n## Functional requirements\n\n- [FR-001](../wiki/functional-requirements/FR-001-lending.md) — Lending.\n\n## Issues\n' \
  > "$OLDFR/_system/index.md"
! "$SCRIPT" sync "$OLDFR" >"$TMP/oldfr-sync.out" 2>&1; check $? "sync refuses a project with pre-notation requirements"
grep -q 'migrate-requirements' "$TMP/oldfr-sync.out" && grep -q 'FR-001-lending.md' "$TMP/oldfr-sync.out"
check $? "the refusal names the migrate-requirements command and the pages"
grep -q '^stereotype: epic' "$OLDFR/wiki/functional-requirements/FR-001-lending.md"; check $? "the refused sync left the pages alone"
"$SCRIPT" migrate-requirements "$OLDFR" >"$TMP/migrate-fr.out" 2>&1; check $? "migrate-requirements succeeds"
fr="$OLDFR/wiki/functional-requirements/FR-001-lending.md"
grep -q '^notation: agile$' "$fr" && grep -q '^level: epic$' "$fr" && ! grep -q '^stereotype:' "$fr"; check $? "stereotype became notation agile + level"
uc="$OLDFR/wiki/functional-requirements/UC-001-find-course.md"
[ -f "$uc" ] && [ ! -e "$OLDFR/wiki/use-cases" ]; check $? "the use case moved into functional-requirements, keeping its ID; use-cases/ gone"
grep -q '^type: functional-requirement$' "$uc" && grep -q '^notation: use-case$' "$uc" && grep -q '^level: sea$' "$uc"
check $? "the use case is an FR in use-case notation, user-goal mapped to sea"
grep -q '^priority: Should$' "$uc" && grep -q '^scope-building-block:' "$uc"; check $? "priority in MoSCoW spelling, scope building block left to fill"
grep -q 'scope-building-block' "$TMP/migrate-fr.out"; check $? "the migration lists the scope building block as a to-do"
! grep -q '^## Use cases' "$OLDFR/_system/index.md" && grep -q 'functional-requirements/UC-001-find-course.md' "$OLDFR/_system/index.md"
check $? "the index lists the use case under Functional requirements"
stk="$OLDFR/wiki/stakeholders/STK-001-learner.md"
grep -qF '[[wiki/functional-requirements/UC-001-find-course|Find course]]' "$stk" \
  && grep -qF '](../functional-requirements/UC-001-find-course.md)' "$stk" && grep -qF '[[UC-001-find-course]]' "$stk"
check $? "path-qualified links follow the moved use case; bare links stay"
! grep -q 'use-cases/' "$stk"; check $? "no link into wiki/use-cases/ is left"
"$SCRIPT" sync "$OLDFR" --force >/dev/null 2>&1; check $? "sync --force succeeds after the migration"

echo "== sync: a product folder held in a git submodule"
SUBP="$TMP/subproj"
"$SCRIPT" new "$SUBP" --name "Sub" >/dev/null 2>&1 || { echo "new (subproj) failed"; exit 1; }
gitq() { git -c user.name=test -c user.email=test@example.invalid -c protocol.file.allow=always "$@"; }
mkdir -p "$TMP/req42-repo" && cp -R "$SRC_ROOT/docs/req42/." "$TMP/req42-repo/"
git -C "$TMP/req42-repo" init -q && gitq -C "$TMP/req42-repo" add -A && gitq -C "$TMP/req42-repo" commit -q -m init
git -C "$SUBP" rm -rq docs/req42 && gitq -C "$SUBP" submodule add -q "$TMP/req42-repo" docs/req42 \
  && gitq -C "$SUBP" commit -q -m "req42 as a submodule"
"$SCRIPT" sync "$SUBP" >"$TMP/sub-clean.out" 2>&1; check $? "sync runs over a clean submodule"
! grep -q 'fatal:' "$TMP/sub-clean.out"; check $? "and no git check fails on its paths"
# git reports a dirty submodule as one path (docs/req42), not as the edited file
echo "edited" >> "$SUBP/docs/req42/README.md"
! "$SCRIPT" sync "$SUBP" >"$TMP/sub-dirty.out" 2>&1; check $? "sync refuses to overwrite an edit inside a submodule"
grep -q '^  docs/req42/README.md$' "$TMP/sub-dirty.out" && tail -1 "$SUBP/docs/req42/README.md" | grep -q edited
check $? "the refusal names the edited file, which stays as it was"
git -C "$SUBP/docs/req42" checkout -q -- README.md
# git settings that hide a submodule's edits from `git status` must not
# hide them from sync: an edited file and an untracked one, under each setting
echo "edited" >> "$SUBP/docs/req42/README.md"
for setting in "submodule.docs/req42.ignore=dirty" "submodule.docs/req42.ignore=untracked" \
               "submodule.docs/req42.ignore=all" "diff.ignoreSubmodules=all"; do
  git -C "$SUBP" config "${setting%%=*}" "${setting#*=}"
  ! "$SCRIPT" sync "$SUBP" >"$TMP/sub-hidden.out" 2>&1 && grep -q '^  docs/req42/README.md$' "$TMP/sub-hidden.out" \
    && tail -1 "$SUBP/docs/req42/README.md" | grep -q edited
  check $? "with $setting, sync still refuses to overwrite the edit"
  git -C "$SUBP" config --unset "${setting%%=*}"
done
git -C "$SUBP/docs/req42" checkout -q -- README.md
# a file the submodule's own repository ignores: only that repository can say so
sm_file="$(cd "$SUBP/docs/req42" && ls | grep -v '^README.md$' | head -1)"
gitq -C "$SUBP/docs/req42" rm -q --cached -- "$sm_file" && gitq -C "$SUBP/docs/req42" commit -q -m untrack \
  && gitq -C "$SUBP" commit -q -am "submodule moved"
printf '%s\n' "$sm_file" >> "$(git -C "$SUBP/docs/req42" rev-parse --absolute-git-dir)/info/exclude"
echo "mine" >> "$SUBP/docs/req42/$sm_file"
! "$SCRIPT" sync "$SUBP" >"$TMP/sub-ignored.out" 2>&1; check $? "sync refuses to overwrite a file the submodule ignores"
grep -q "^  docs/req42/$sm_file\$" "$TMP/sub-ignored.out"; check $? "the refusal names it"
# when a safety check cannot be completed, sync stops instead of guessing
mkdir -p "$TMP/badgit" && cat > "$TMP/badgit/git" <<EOF
#!/bin/sh
case " \$* " in *" check-ignore "*) echo "fatal: simulated failure" >&2; exit 128 ;; esac
exec "$(command -v git)" "\$@"
EOF
chmod +x "$TMP/badgit/git"
! PATH="$TMP/badgit:$PATH" "$SCRIPT" sync "$SUBP" >"$TMP/sub-fail.out" 2>&1; check $? "sync stops when the git-ignore check fails"
grep -q 'could not check' "$TMP/sub-fail.out" && grep -q 'mine' "$SUBP/docs/req42/$sm_file"
check $? "it says so and changes nothing"

echo "== harvest: --out into a missing directory"
! "$SCRIPT" harvest "$TARGET" --out "$TMP/no/such/dir/h.patch" >"$TMP/harvest-badout.out" 2>&1
check $? "harvest refuses an --out whose directory does not exist"
grep -q 'does not exist' "$TMP/harvest-badout.out"; check $? "the refusal names the missing directory"

echo "== harvest refuses a non-project directory"
mkdir -p "$TMP/not-a-project"
! "$SCRIPT" harvest "$TMP/not-a-project" >/dev/null 2>&1; check $? "harvest refuses a directory without _system/wiki.yaml"

echo "== legacy project: glossary and data-model pages"
OLDTERMS="$TMP/oldterms"
"$SCRIPT" new "$OLDTERMS" --name "Legacy terms" --no-git >/dev/null 2>&1 || exit 1
mkdir -p "$OLDTERMS/wiki/glossary" "$OLDTERMS/wiki/data-models"
cat > "$OLDTERMS/wiki/glossary/GLO-001-training.md" <<'EOF'
---
id: GLO-001
type: glossary-term
title: Training
status: accepted
created: 2026-10-01
related: ["[[DM-001-training]]"]
---
**Definition.** A Training.
EOF
cat > "$OLDTERMS/wiki/glossary/GLO-003-provider.md" <<'EOF'
---
id: GLO-003
type: glossary-term
title: Provider
status: draft
---
**Definition.** A Provider.
EOF
cat > "$OLDTERMS/wiki/data-models/DM-001-training.md" <<'EOF'
---
id: DM-001
type: data-model
status: draft
stereotype: entity
related: ["[[GLO-001-training]]", "[[GLO-003-provider]]"]
relationships:
- {target: "[[DM-002-session]]", verb: holds, kind: composition, cardinality: "1..*"}
---
**Attributes.**
- `name` : string mandatory — training name.
EOF
cat > "$OLDTERMS/wiki/data-models/DM-002-session.md" <<'EOF'
---
id: DM-002
type: data-model
title: Session
status: draft
stereotype: value-object
---
**Definition.** A Session.
EOF
cat > "$OLDTERMS/raw/sources/SRC-001-training.md" <<'EOF'
---
ingested-pages:
- "[[DM-001-training]]"
---
Historical mention: [[DM-001-training]].
EOF
printf '%s\n' '[[wiki/data-models/DM-001-training|training]] and [session](../data-models/DM-002-session.md).' \
    > "$OLDTERMS/wiki/stakeholders/STK-001-teacher.md"
! "$SCRIPT" sync "$OLDTERMS" > "$TMP/oldterms-sync.out" 2>&1 &&
    grep -q 'migrate-domain-terms' "$TMP/oldterms-sync.out"
check $? "sync refuses legacy domain terms and names the migration"
cp -R "$OLDTERMS" "$TMP/oldterms-before"
python3 "$HERE/migrate-domain-terms.py" --dry-run "$OLDTERMS" > "$TMP/dt-preview.out" &&
    diff -r "$OLDTERMS/wiki" "$TMP/oldterms-before/wiki" >/dev/null &&
    diff -r "$OLDTERMS/raw" "$TMP/oldterms-before/raw" >/dev/null &&
    cmp -s "$OLDTERMS/_system/index.md" "$TMP/oldterms-before/_system/index.md"
check $? "domain-term dry run writes nothing"
"$SCRIPT" migrate-domain-terms "$OLDTERMS" > "$TMP/dt-migration.out" 2>&1
check $? "migrate-domain-terms succeeds"
training="$OLDTERMS/wiki/domain-terms/DT-001-training.md"
grep -q '^status: review$' "$training" && grep -q '^attributes:$' "$training" &&
    grep -q 'to:.*DT-002-session' "$training" && grep -q 'multiplicity: 1\.\.\*' "$training"
check $? "a merged term holds its definition, attributes and UML relationship"
grep -qF '[[wiki/domain-terms/DT-001-training|training]]' "$OLDTERMS/wiki/stakeholders/STK-001-teacher.md" &&
    grep -qF '../domain-terms/DT-002-session.md' "$OLDTERMS/wiki/stakeholders/STK-001-teacher.md" &&
    grep -qF '[[DT-001-training]]' "$OLDTERMS/raw/sources/SRC-001-training.md" &&
    grep -qF 'Historical mention: [[DM-001-training]]' "$OLDTERMS/raw/sources/SRC-001-training.md"
check $? "migration rewrites wiki links and provenance frontmatter"
"$SCRIPT" sync "$OLDTERMS" > "$TMP/dt-sync.out" 2>&1 &&
    python3 "$OLDTERMS/_system/scripts/metamodel-lint.py" > "$TMP/dt-lint.out" 2>&1
check $? "migrated terms sync and pass metamodel lint"

echo "== sync refuses a non-project directory"
mkdir -p "$TMP/not-a-project"
! "$SCRIPT" sync "$TMP/not-a-project" >/dev/null 2>&1; check $? "refuses a directory without _system/wiki.yaml"

echo
if [ "$failures" -eq 0 ]; then echo "all checks passed"; else echo "$failures check(s) failed"; exit 1; fi
