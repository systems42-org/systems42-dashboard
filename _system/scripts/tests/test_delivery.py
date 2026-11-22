"""`_system/scripts/delivery.py` (FR-031, FR-032) against a throwaway Git
repository: the baseline is found and the right content is compared. No pytest
dependency.

Run from the repository root:
    python3 _system/scripts/tests/test_delivery.py
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
SCRIPT = REPO / "_system" / "scripts" / "delivery.py"
ENV = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@localhost",
       "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@localhost"}

PAGE = """---
id: FR-001
type: functional-requirement
title: Ship orders
notation: agile
level: story
delivery: implemented
delivery-checked: 2026-10-28T10:00:00+01:00
---

# Ship orders

As a customer I want my order shipped.

Example rule:
delivery: next-day
"""


class Vault:
    def __init__(self, root: Path):
        self.root = root
        self.wiki = root / "wiki" / "functional-requirements"
        self.wiki.mkdir(parents=True)
        self.git("init", "-q")

    def git(self, *args):
        subprocess.run(["git", "-C", str(self.root), *args], check=True, env=ENV,
                       capture_output=True)

    def commit(self, msg):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", msg)

    def check(self, *args):
        r = subprocess.run([sys.executable, str(SCRIPT), "--root", str(self.root), *args],
                           capture_output=True, text=True)
        assert "Traceback" not in r.stderr, r.stderr
        return r.stdout


def _vault(fn):
    with tempfile.TemporaryDirectory() as tmp:
        fn(Vault(Path(tmp)))


def test_page_added_with_delivery_is_its_own_baseline():
    def run(v):
        (v.wiki / "FR-001-ship-orders.md").write_text(PAGE, encoding="utf-8")
        v.commit("add FR-001 already delivered")
        out = v.check("--dry-run")
        assert out.startswith("OK FR-001"), out
    _vault(run)


def test_body_lines_that_look_like_delivery_fields_are_content():
    def run(v):
        page = v.wiki / "FR-001-ship-orders.md"
        page.write_text(PAGE, encoding="utf-8")
        v.commit("add")
        page.write_text(PAGE.replace("delivery: next-day", "delivery: same-day"), encoding="utf-8")
        out = v.check("--dry-run")
        assert out.startswith("DRIFT FR-001"), out
        assert "+delivery: same-day" in out, out
    _vault(run)


def test_drift_marks_outdated_and_keeps_the_baseline():
    def run(v):
        page = v.wiki / "FR-001-ship-orders.md"
        page.write_text(PAGE, encoding="utf-8")
        v.commit("add")
        page.write_text(PAGE.replace("shipped.", "shipped today."), encoding="utf-8")
        assert v.check().startswith("DRIFT FR-001"), "first run"
        assert "delivery: outdated" in page.read_text(encoding="utf-8")
        v.commit("inspect marks outdated")
        out = v.check()
        assert "already outdated" in out, out
    _vault(run)


def test_marking_outdated_changes_only_the_delivery_line():
    def run(v):
        page = v.wiki / "FR-001-ship-orders.md"
        page.write_text(PAGE, encoding="utf-8")
        v.commit("add")
        drifted = PAGE.replace("shipped.", "shipped today.")
        page.write_text(drifted, encoding="utf-8")
        assert v.check().startswith("DRIFT FR-001"), "first run"
        expected = drifted.replace("delivery: implemented", "delivery: outdated")
        assert page.read_text(encoding="utf-8") == expected, page.read_text(encoding="utf-8")
    _vault(run)


def test_renamed_page_keeps_its_baseline():
    def run(v):
        old = v.wiki / "FR-001-ship-orders.md"
        old.write_text(PAGE, encoding="utf-8")
        v.commit("add")
        v.git("mv", str(old), str(v.wiki / "FR-001-ship-all-orders.md"))
        v.commit("rename only")
        out = v.check("--dry-run")
        assert out.startswith("OK FR-001"), out
        new = v.wiki / "FR-001-ship-all-orders.md"
        new.write_text(PAGE.replace("shipped.", "shipped fast."), encoding="utf-8")
        out = v.check("--dry-run")
        assert out.startswith("DRIFT FR-001"), out
    _vault(run)


USE_CASE = """---
id: UC-001
type: functional-requirement
title: Order goods
notation: use-case
level: sea
delivery: implemented
delivery-checked: 2026-10-28T10:00:00+01:00
---

# Order goods
"""


def test_outdated_refining_story_reports_the_use_case():
    def run(v):
        (v.wiki / "UC-001-order-goods.md").write_text(USE_CASE, encoding="utf-8")
        story = v.wiki / "FR-001-ship-orders.md"
        story.write_text(PAGE.replace("level: story\n", "level: story\nparent: [\"[[UC-001-order-goods]]\"]\n"),
                         encoding="utf-8")
        v.commit("add use case and refining story")
        assert "REVIEW" not in v.check("--dry-run")
        story.write_text(story.read_text(encoding="utf-8").replace("shipped.", "shipped today."),
                         encoding="utf-8")
        out = v.check("--dry-run", "FR-001")
        assert "DRIFT FR-001" in out, out
        assert "REVIEW UC-001: refining story FR-001 is outdated" in out, out
        assert "delivery: implemented" in (v.wiki / "UC-001-order-goods.md").read_text(encoding="utf-8")
    _vault(run)


def _uc_with_story(v, parent_link="[[UC-001-order-goods]]"):
    (v.wiki / "UC-001-order-goods.md").write_text(USE_CASE, encoding="utf-8")
    story = v.wiki / "FR-001-ship-orders.md"
    story.write_text(PAGE.replace("level: story\n", f'level: story\nparent: ["{parent_link}"]\n'),
                     encoding="utf-8")
    v.commit("add use case and refining story")
    return story


def test_path_qualified_parent_link_still_finds_the_story():
    def run(v):
        story = _uc_with_story(v, "[[wiki/functional-requirements/UC-001-order-goods|order]]")
        story.write_text(story.read_text(encoding="utf-8").replace("shipped.", "shipped today."),
                         encoding="utf-8")
        out = v.check("--dry-run", "FR-001")
        assert "REVIEW UC-001: refining story FR-001 is outdated" in out, out
    _vault(run)


def test_targeted_use_case_check_includes_its_stories():
    def run(v):
        story = _uc_with_story(v)
        story.write_text(story.read_text(encoding="utf-8").replace("shipped.", "shipped today."),
                         encoding="utf-8")
        out = v.check("--dry-run", "UC-001")
        assert "DRIFT FR-001" in out, out
        assert "REVIEW UC-001" in out, out
    _vault(run)


def test_targeted_check_ignores_unrelated_use_cases():
    def run(v):
        story = _uc_with_story(v)
        other = v.wiki / "FR-002-other.md"
        other.write_text(PAGE.replace("id: FR-001", "id: FR-002").replace("Ship orders", "Refund payments")
                         .replace("my order shipped", "a refund paid out").replace("customer", "buyer")
                         .replace("Example rule:\ndelivery: next-day", "Unrelated body text."),
                         encoding="utf-8")
        v.commit("add unrelated story")
        story.write_text(story.read_text(encoding="utf-8").replace("shipped.", "shipped today."),
                         encoding="utf-8")
        assert "marked outdated" in v.check("FR-001")
        v.commit("story drifted")
        out = v.check("--dry-run", "FR-002")
        assert out.startswith("OK FR-002") and "REVIEW" not in out, out
    _vault(run)


if __name__ == "__main__":
    test_page_added_with_delivery_is_its_own_baseline()
    test_body_lines_that_look_like_delivery_fields_are_content()
    test_drift_marks_outdated_and_keeps_the_baseline()
    test_marking_outdated_changes_only_the_delivery_line()
    test_renamed_page_keeps_its_baseline()
    test_outdated_refining_story_reports_the_use_case()
    test_path_qualified_parent_link_still_finds_the_story()
    test_targeted_use_case_check_includes_its_stories()
    test_targeted_check_ignores_unrelated_use_cases()
    print("ALL PASSED")
