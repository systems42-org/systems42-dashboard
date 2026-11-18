"""`./dashboard.sh publish` (dev.sh) sets the release tag only when a release
can go right. No pytest.

Each case runs the real dev.sh in a throwaway clone with a throwaway origin.
`docker` is a stub, so "the tests" pass or fail as the case says.

Run from the dashboard dir:
    .venv/bin/python tests/test_publish.py
"""
import os
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
ENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.org",
           GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.org",
           GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull)


def git(cwd, *args):
    run = subprocess.run(["git", *args], cwd=cwd, env=ENV, capture_output=True, text=True)
    assert run.returncode == 0, (args, run.stderr)
    return run.stdout.strip()


def repo(tmp: Path, version="1.2.0", changelog="Dashboard release 1.2.0", tags=()):
    """A clone on main, equal to its origin, with dev.sh, VERSION and a changelog."""
    origin, work = tmp / "origin.git", tmp / "work"
    git(tmp, "init", "-q", "--bare", "-b", "main", str(origin))
    git(tmp, "clone", "-q", str(origin), str(work))
    git(work, "checkout", "-q", "-b", "main")
    dash = work / "_system" / "apps" / "dashboard"
    dash.mkdir(parents=True)
    shutil.copy(HERE / "dev.sh", dash / "dev.sh")
    (dash / "VERSION").write_text(version + "\n", encoding="utf-8")
    (work / "CHANGELOG.md").write_text(changelog + "\n", encoding="utf-8")
    git(work, "add", "-A")
    git(work, "commit", "-q", "-m", "start")
    for tag in tags:
        git(work, "tag", tag)
    git(work, "push", "-q", "origin", "main", "--tags")
    return origin, work


def publish(tmp: Path, work: Path, tests_pass=True):
    bin_dir = tmp / "bin"
    bin_dir.mkdir(exist_ok=True)
    stub = bin_dir / "docker"
    stub.write_text(f"#!/bin/sh\nexit {0 if tests_pass else 1}\n", encoding="utf-8")
    stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
    env = dict(ENV, PATH=f"{bin_dir}{os.pathsep}{ENV['PATH']}")
    return subprocess.run(["bash", str(work / "_system/apps/dashboard/dev.sh"), "publish"],
                          cwd=work, env=env, capture_output=True, text=True)


def tags_at(origin: Path):
    return git(origin, "tag", "-l").split()


def refused(run, origin, word, before=()):
    assert run.returncode == 1, (run.stdout, run.stderr)
    assert word in run.stderr, run.stderr
    assert sorted(tags_at(origin)) == sorted(before), "a refused release must leave no tag"


def test_a_good_release_is_tagged_on_main_and_pushed():
    with tempfile.TemporaryDirectory() as d:
        origin, work = repo(Path(d), tags=("v1.1.0", "v1.1.9"))
        run = publish(Path(d), work)
        assert run.returncode == 0, (run.stdout, run.stderr)
        assert "v1.2.0" in tags_at(origin)
        assert git(origin, "rev-parse", "v1.2.0") == git(work, "rev-parse", "HEAD")
        assert "release 1.2.0" in run.stdout


def test_an_existing_release_is_refused():
    with tempfile.TemporaryDirectory() as d:
        origin, work = repo(Path(d), tags=("v1.2.0",))
        refused(publish(Path(d), work), origin, "exists already", before=("v1.2.0",))


def test_a_tag_only_the_origin_has_is_seen():
    """Someone else published it: the tag is at the origin, not in this clone."""
    with tempfile.TemporaryDirectory() as d:
        origin, work = repo(Path(d), tags=("v1.2.0",))
        git(work, "tag", "-d", "v1.2.0")
        refused(publish(Path(d), work), origin, "exists already", before=("v1.2.0",))


def test_a_release_lower_than_the_newest_is_refused():
    with tempfile.TemporaryDirectory() as d:
        origin, work = repo(Path(d), version="1.2.0", tags=("v1.10.0",))
        refused(publish(Path(d), work), origin, "lower than the newest", before=("v1.10.0",))


def test_only_main_equal_to_origin_and_clean_is_published():
    with tempfile.TemporaryDirectory() as d:
        origin, work = repo(Path(d))
        git(work, "checkout", "-q", "-b", "feature")
        refused(publish(Path(d), work), origin, "from main")
        git(work, "checkout", "-q", "main")
        (work / "CHANGELOG.md").write_text("Dashboard release 1.2.0, edited\n", encoding="utf-8")
        refused(publish(Path(d), work), origin, "uncommitted")
        git(work, "commit", "-q", "-am", "not pushed")
        refused(publish(Path(d), work), origin, "differs from origin/main")


def test_a_release_the_changelog_does_not_name_is_refused():
    with tempfile.TemporaryDirectory() as d:
        origin, work = repo(Path(d), changelog="Dashboard release 1.1.0")
        refused(publish(Path(d), work), origin, "CHANGELOG.md")
    with tempfile.TemporaryDirectory() as d:
        origin, work = repo(Path(d), version="1.2", changelog="1.2")
        refused(publish(Path(d), work), origin, "not a release number")


def test_failing_tests_publish_nothing():
    with tempfile.TemporaryDirectory() as d:
        origin, work = repo(Path(d))
        refused(publish(Path(d), work, tests_pass=False), origin, "tests failed")
        assert git(work, "tag", "-l") == ""


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("ok")
