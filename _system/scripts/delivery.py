#!/usr/bin/env python3
"""Check delivered functional requirements against their Git baseline.

The baseline is the newest commit that changed either `delivery` or
`delivery-checked` and whose resulting delivery state is `implemented` or
`partial`. An automatic transition to `outdated` does not replace that baseline.
The script compares the current page with its baseline version while ignoring
the two delivery frontmatter fields. Detected drift marks active delivery `outdated`
and prints a unified diff for human review.

Run from the vault root:
    python3 _system/scripts/delivery.py [FR-ID ...]
Use --dry-run to report drift without changing the page.
"""
from __future__ import annotations

import argparse
import difflib
import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("delivery.py needs PyYAML: pip install pyyaml")

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fr_hierarchy  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WIKI = ROOT / "wiki" / "functional-requirements"
FM = re.compile(r"\A---\s*\n(.*?)\n---\s*\n", re.DOTALL)
TRACKED_FIELDS = re.compile(r"^(?:delivery|delivery-checked)\s*:")
DELIVERY_VALUES = {"partial", "implemented", "outdated", "removed"}


def git(*args: str, root: Path = ROOT) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), *args], text=True, capture_output=True, check=False
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or f"git {' '.join(args)} failed")
    return result.stdout


def metadata(text: str) -> dict:
    match = FM.match(text)
    if not match:
        raise ValueError("page has no YAML frontmatter")
    data = yaml.safe_load(match.group(1)) or {}
    if not isinstance(data, dict):
        raise ValueError("page frontmatter is not a YAML mapping")
    return data


def strip_delivery_lines(text: str) -> str:
    """Remove the two delivery fields from the frontmatter only. The same text
    in the body (an example, a quoted rule) is requirement content (FR-032)."""
    match = FM.match(text)
    if not match:
        return text
    kept = "".join(line for line in match.group(1).splitlines(keepends=True)
                   if not TRACKED_FIELDS.match(line)).rstrip("\n")
    return text[:match.start(1)] + kept + text[match.end(1):]


def lenient_metadata(text: str) -> dict:
    """Frontmatter of one historical version, or {} if it has none (e.g. the
    page did not exist before the commit)."""
    try:
        return metadata(text)
    except (ValueError, yaml.YAMLError):
        return {}


def delivery_history(relative: str, root: Path) -> list[tuple[str, str, str]]:
    """Commits that touched a delivery line, newest first, as (commit, path
    before, path after). Paths are per commit, so a renamed page is read under
    the name it had then."""
    out = git("log", "--follow", "--format=commit %H", "--name-status", "-G",
              r"^delivery(-checked)?:", "--", relative, root=root)
    history: list[tuple[str, str, str]] = []
    commit = None
    for line in out.splitlines():
        if line.startswith("commit "):
            commit = line.split()[1]
        elif line.strip() and commit:
            parts = line.split("\t")
            if parts[0].startswith(("R", "C")) and len(parts) == 3:
                history.append((commit, parts[1], parts[2]))
            else:
                history.append((commit, parts[-1], parts[-1]))
            commit = None
    return history


def baseline_commit(path: Path, root: Path) -> tuple[str, str] | None:
    """Return the latest commit that recorded a checked active delivery, and
    the page's path in that commit.

    A drift finding may write ``delivery: outdated``. That transition must not
    become a new implementation baseline, or the next run would hide the drift.
    Only commits whose resulting state is ``implemented`` or ``partial`` count.
    """
    relative = path.relative_to(root).as_posix()
    for commit, before_path, after_path in delivery_history(relative, root):
        # `-G` can include a patch where a body line matches; verify the
        # frontmatter values themselves changed in this commit.
        try:
            before = git("show", f"{commit}^:{before_path}", root=root)
        except RuntimeError:
            before = ""  # the page was added in this commit
        try:
            after = git("show", f"{commit}:{after_path}", root=root)
        except RuntimeError:
            continue
        before_meta, after_meta = lenient_metadata(before), lenient_metadata(after)
        fields_changed = any(before_meta.get(key) != after_meta.get(key)
                             for key in ("delivery", "delivery-checked"))
        if fields_changed and after_meta.get("delivery") in {"implemented", "partial"}:
            return commit, after_path
    return None


def page_for_id(requirement_id: str, wiki: Path) -> Path | None:
    for path in sorted(wiki.glob("*.md")):
        try:
            if str(metadata(path.read_text(encoding="utf-8")).get("id", "")) == requirement_id:
                return path
        except (OSError, ValueError, yaml.YAMLError):
            continue
    return None


def write_delivery(path: Path, text: str, state: str) -> None:
    match = FM.match(text)
    if not match:
        raise ValueError("page has no YAML frontmatter")
    frontmatter = match.group(1)
    if re.search(r"^delivery\s*:", frontmatter, re.M):
        frontmatter = re.sub(r"^delivery\s*:.*$", f"delivery: {state}", frontmatter,
                             count=1, flags=re.M)
    else:
        frontmatter += f"\ndelivery: {state}"
    # Replace only the frontmatter body; the delimiters and the blank lines
    # around them stay as the author wrote them.
    path.write_text(text[:match.start(1)] + frontmatter + text[match.end(1):], encoding="utf-8")


def inspect_page(path: Path, dry_run: bool, root: Path) -> tuple[bool, str]:
    text = path.read_text(encoding="utf-8")
    data = metadata(text)
    requirement_id = str(data.get("id") or path.stem)
    state = str(data.get("delivery") or "").strip()
    if state not in {"implemented", "partial", "outdated"}:
        return False, f"SKIP {requirement_id}: delivery is {state or 'absent'}"
    if not data.get("delivery-checked"):
        return True, f"ERROR {requirement_id}: delivery has no delivery-checked timestamp"

    found = baseline_commit(path, root)
    if not found:
        return True, (f"ERROR {requirement_id}: no committed change to delivery or "
                      "delivery-checked found; commit the delivery record first")
    baseline, baseline_path = found
    try:
        baseline_text = git("show", f"{baseline}:{baseline_path}", root=root)
    except RuntimeError as exc:
        return True, f"ERROR {requirement_id}: cannot read baseline {baseline[:12]}: {exc}"

    old = strip_delivery_lines(baseline_text).splitlines(keepends=True)
    current = strip_delivery_lines(text).splitlines(keepends=True)
    if old == current:
        return False, f"OK {requirement_id}: no requirement-content drift since {baseline[:12]}"

    diff = "".join(difflib.unified_diff(
        old, current, fromfile=f"{requirement_id} at {baseline[:12]}",
        tofile=f"{requirement_id} current", n=3,
    ))
    lines = [f"DRIFT {requirement_id}: content changed since {baseline[:12]}", diff]
    if state != "outdated" and not dry_run:
        write_delivery(path, text, "outdated")
        lines[0] += " (marked outdated)"
    elif state != "outdated":
        lines[0] += " (dry run; not changed)"
    else:
        lines[0] += " (already outdated; no duplicate finding)"
    return True, "\n".join(lines)


def load_pages(wiki: Path) -> dict[str, dict]:
    pages: dict[str, dict] = {}
    for path in sorted(wiki.glob("*.md")):
        try:
            pages[path.stem] = metadata(path.read_text(encoding="utf-8"))
        except (OSError, ValueError, yaml.YAMLError):
            continue
    return pages


def refining_stories_of(selected: set[str], pages: dict[str, dict]) -> set[str]:
    """Stories refining a selected use case, so a targeted check sees their drift too."""
    children = fr_hierarchy.agile_children(pages)
    out: set[str] = set()
    for stem in selected:
        if str(pages.get(stem, {}).get("notation") or "") == "use-case":
            out |= set(fr_hierarchy.refining_stories(stem, pages, children)[0])
    return out


def use_cases_to_recheck(pages: dict[str, dict], drifted: set[str],
                         selected: set[str] | None = None) -> list[str]:
    """Use cases with active delivery that an `outdated` Agile story refines,
    directly or through a refining feature (FR-031, DR-038 amendment). They are
    reported for a human recheck; their delivery is never changed here.
    `drifted` holds stems found drifting in this run, so a dry run reports them
    as if they had been marked. With `selected`, only use cases that are selected
    or refined by a selected story are reported."""
    children = fr_hierarchy.agile_children(pages)
    out = []
    for stem, data in pages.items():
        if (str(data.get("notation") or "") != "use-case"
                or data.get("delivery") not in {"implemented", "partial"}):
            continue
        stories = fr_hierarchy.refining_stories(stem, pages, children)[0]
        if selected is not None and stem not in selected and not selected & set(stories):
            continue
        for story in stories:
            if pages[story].get("delivery") == "outdated" or story in drifted:
                use_case_id = str(data.get("id") or stem)
                story_id = str(pages[story].get("id") or story)
                out.append(f"REVIEW {use_case_id}: refining story {story_id} is outdated; "
                           f"recheck the use case (its delivery is unchanged)")
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("requirements", nargs="*", help="FR IDs; default checks all delivered pages")
    parser.add_argument("--root", type=Path, default=ROOT, help="vault Git root (default: repo root)")
    parser.add_argument("--dry-run", action="store_true", help="report drift without changing pages")
    args = parser.parse_args()
    root = args.root.resolve()
    wiki = root / "wiki" / "functional-requirements"
    if not (root / ".git").exists():
        print(f"ERROR: {root} is not a Git worktree", file=sys.stderr)
        return 2
    if args.requirements:
        paths = []
        for requirement_id in args.requirements:
            path = page_for_id(requirement_id, wiki)
            if path is None:
                print(f"ERROR {requirement_id}: functional requirement not found")
                return 2
            paths.append(path)
        pages = load_pages(wiki)
        selected = {p.stem for p in paths}
        extra = refining_stories_of(selected, pages) - selected
        paths += [wiki / f"{stem}.md" for stem in sorted(extra)]
        selected |= extra
    else:
        paths = sorted(wiki.glob("*.md"))
        selected = None

    drift_or_error = False
    drifted: set[str] = set()
    for path in paths:
        try:
            finding, output = inspect_page(path, args.dry_run, root)
        except (OSError, ValueError, yaml.YAMLError, RuntimeError) as exc:
            finding, output = True, f"ERROR {path.name}: {exc}"
        print(output)
        drift_or_error |= finding
        if output.startswith("DRIFT"):
            drifted.add(path.stem)
    for line in use_cases_to_recheck(load_pages(wiki), drifted, selected):
        print(line)
        drift_or_error = True
    return 1 if drift_or_error else 0


if __name__ == "__main__":
    sys.exit(main())
