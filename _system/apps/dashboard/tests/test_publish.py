"""The release commands of dev.sh. `./dashboard.sh version X.Y.Z` raises
VERSION on a branch, `./dashboard.sh publish` sets the release tag only when a
release can go right, and every refusal says what to do next. No pytest.

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


def dev(tmp: Path, work: Path, *args, tests_pass=True):
    """Run dev.sh with stubs: `docker` (the tests) and `gh` (the pull request)."""
    bin_dir = tmp / "bin"
    bin_dir.mkdir(exist_ok=True)
    for name, body in (("docker", f"exit {0 if tests_pass else 1}"),
                       ("gh", f'echo "$@" > "{tmp}/gh.args"; echo https://example.org/pull/7')):
        stub = bin_dir / name
        stub.write_text(f"#!/bin/sh\n{body}\n", encoding="utf-8")
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
    env = dict(ENV, PATH=f"{bin_dir}{os.pathsep}{ENV['PATH']}")
    return subprocess.run(["bash", str(work / "_system/apps/dashboard/dev.sh"), *args],
                          cwd=work, env=env, capture_output=True, text=True)


def publish(tmp: Path, work: Path, tests_pass=True):
    return dev(tmp, work, "publish", tests_pass=tests_pass)


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
        run = publish(Path(d), work)
        refused(run, origin, "published already", before=("v1.2.0",))
        # the refusal says how to go on
        assert "make version V=1.2.1" in run.stderr and "make publish again" in run.stderr, run.stderr


def test_a_tag_only_the_origin_has_is_seen():
    """Someone else published it: the tag is at the origin, not in this clone."""
    with tempfile.TemporaryDirectory() as d:
        origin, work = repo(Path(d), tags=("v1.2.0",))
        git(work, "tag", "-d", "v1.2.0")
        refused(publish(Path(d), work), origin, "published already", before=("v1.2.0",))


def test_a_release_lower_than_the_newest_is_refused():
    with tempfile.TemporaryDirectory() as d:
        origin, work = repo(Path(d), version="1.2.0", tags=("v1.10.0",))
        run = publish(Path(d), work)
        refused(run, origin, "lower than the newest", before=("v1.10.0",))
        assert "make version V=1.10.1" in run.stderr, run.stderr


def test_only_main_without_changes_of_its_own_is_published():
    with tempfile.TemporaryDirectory() as d:
        origin, work = repo(Path(d))
        git(work, "checkout", "-q", "-b", "feature")
        refused(publish(Path(d), work), origin, "git checkout main")
        git(work, "checkout", "-q", "main")
        (work / "CHANGELOG.md").write_text("Dashboard release 1.2.0, edited\n", encoding="utf-8")
        refused(publish(Path(d), work), origin, "uncommitted")
        git(work, "commit", "-q", "-am", "not pushed")
        refused(publish(Path(d), work), origin, "origin/main does not have")


def test_a_main_that_is_only_behind_is_brought_up_to_date():
    """The usual case after merging the version pull request on GitHub."""
    with tempfile.TemporaryDirectory() as d:
        origin, work = repo(Path(d), version="1.1.0", changelog="Dashboard release 1.1.0", tags=("v1.1.0",))
        other = Path(d) / "other"
        git(Path(d), "clone", "-q", str(origin), str(other))
        (other / "_system/apps/dashboard/VERSION").write_text("1.2.0\n", encoding="utf-8")
        (other / "CHANGELOG.md").write_text("Dashboard release 1.2.0\n", encoding="utf-8")
        git(other, "commit", "-q", "-am", "Dashboard release 1.2.0")
        git(other, "push", "-q", "origin", "main")
        run = publish(Path(d), work)
        assert run.returncode == 0, (run.stdout, run.stderr)
        assert "now up to date" in run.stdout
        assert git(origin, "rev-parse", "v1.2.0") == git(other, "rev-parse", "HEAD")


def test_version_raises_it_on_a_branch_with_a_pull_request():
    with tempfile.TemporaryDirectory() as d:
        log = "# Changelog\n\n## [Unreleased]\n\n### Added\n- A thing.\n\n### Changed\n- Older.\n\n## [0.1]\n\n### Changed\n- Old.\n"
        origin, work = repo(Path(d), version="1.2.0", changelog=log, tags=("v1.2.0",))
        run = dev(Path(d), work, "version", "1.3.0")
        assert run.returncode == 0, (run.stdout, run.stderr)
        assert git(work, "rev-parse", "--abbrev-ref", "HEAD") == "main", "it returns to main"
        assert git(work, "show", "main:_system/apps/dashboard/VERSION") == "1.2.0", "main is untouched"
        assert git(origin, "show", "release-1.3.0:_system/apps/dashboard/VERSION") == "1.3.0"
        changed = git(origin, "show", "release-1.3.0:CHANGELOG.md")
        want = "### Changed\n- Dashboard release 1.3.0 (`_system/apps/dashboard/VERSION`).\n- Older."
        assert want in changed and changed.count("Dashboard release 1.3.0") == 1, changed
        assert changed.count("### Changed") == 2, "no new heading when the unreleased part has one"
        assert git(origin, "diff", "--name-only", "main", "release-1.3.0").split() == \
            ["CHANGELOG.md", "_system/apps/dashboard/VERSION"]
        # the pull request is opened, and the next two steps are named
        assert "--head release-1.3.0" in (Path(d) / "gh.args").read_text(encoding="utf-8")
        assert "https://example.org/pull/7" in run.stdout and "make publish" in run.stdout, run.stdout


def test_version_adds_the_changelog_heading_when_there_is_none():
    for log in ("# Changelog\n\n## [Unreleased]\n\n### Added\n- A thing.\n\n## [0.1]\n\n### Changed\n- Old.\n",
                "# Changelog\n\n## [Unreleased]\n\n### Added\n- A thing.\n"):
        with tempfile.TemporaryDirectory() as d:
            origin, work = repo(Path(d), version="1.2.0", changelog=log)
            assert dev(Path(d), work, "version", "1.2.1").returncode == 0
            changed = git(origin, "show", "release-1.2.1:CHANGELOG.md")
            new = "### Changed\n- Dashboard release 1.2.1 (`_system/apps/dashboard/VERSION`)."
            assert changed.count(new) == 1, changed
            if "## [0.1]" in log:
                assert changed.index(new) < changed.index("## [0.1]"), changed


def test_version_refuses_what_is_not_a_step_up():
    with tempfile.TemporaryDirectory() as d:
        origin, work = repo(Path(d), version="1.2.0", tags=("v1.2.0", "v1.4.0"))
        for bad, hint in (("1.2.0", "make version V=1.2.1"), ("1.1.9", "make version V=1.2.1"),
                          ("1.3.0", "make version V=1.4.1"), ("1.4.0", "make version V=1.4.1")):
            run = dev(Path(d), work, "version", bad)
            assert run.returncode == 1 and hint in run.stderr, (bad, run.stderr)
        run = dev(Path(d), work, "version", "2.0")
        assert run.returncode == 1 and "not a release number" in run.stderr, run.stderr
        assert git(origin, "branch", "--list", "release-*") == "", "a refusal makes no branch"
        assert git(work, "rev-parse", "--abbrev-ref", "HEAD") == "main"


def test_version_without_a_number_says_which_is_next():
    with tempfile.TemporaryDirectory() as d:
        origin, work = repo(Path(d), version="1.2.9")
        run = dev(Path(d), work, "version")
        assert run.returncode == 2 and "at 1.2.9" in run.stderr and "make version V=1.2.10" in run.stderr, run.stderr


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


def test_no_variable_runs_into_a_non_ascii_character():
    """macOS ships bash 3.2, which reads `$version…` as a variable named
    `version…` and stops. The tests run on a newer bash and do not see it."""
    import re
    for script in (HERE / "dev.sh", HERE.parents[2] / "dashboard.sh"):
        text = script.read_text(encoding="utf-8")
        assert not re.findall(r"\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7f]", text), script.name


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("ok")
