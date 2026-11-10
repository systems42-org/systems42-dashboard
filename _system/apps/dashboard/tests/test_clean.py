"""`make clean` removes what can be rebuilt and nothing else. No pytest.

Runs the real Makefile and dashboard.sh in a throwaway copy of the repo layout,
with a stub `docker` on PATH: the test never touches this repo's files, its
container or its image.

Run from the dashboard dir:
    .venv/bin/python tests/test_clean.py
"""
import os
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

_REPO = Path(__file__).resolve().parents[4]

REBUILDABLE = [
    "_system/apps/dashboard/.venv/bin/python",
    "_system/apps/dashboard/__pycache__/app.cpython-39.pyc",
    "_system/scripts/__pycache__/x.pyc",
    ".DS_Store",
    "_system/.DS_Store",
]
KEPT = [
    "wiki/glossary/GLO-001-term.md",
    "wiki/.DS_Store",
    "wiki/__pycache__/looks-like-junk.pyc",
    "raw/interview.md",
    "raw/.DS_Store",
    "raw/sources/SRC-001.md",
    "docs/about.md",
    "sandbox/note.md",
    "_system/wiki.yaml",
    "_system/dashboard.yaml",
    "harvest-foo.patch",
    ".git/.DS_Store",
    ".obsidian/workspace.json",
    "_system/apps/dashboard/compose.yaml",
    "_system/apps/dashboard/app.py",
]


def _vault(tmp):
    root = Path(tmp) / "vault"
    for rel in REBUILDABLE + KEPT:
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("x", encoding="utf-8")
    shutil.copy(_REPO / "dashboard.sh", root / "dashboard.sh")
    shutil.copy(_REPO / "Makefile", root / "Makefile")
    return root


def _stub_docker(tmp, exit_code):
    """A `docker` that logs its arguments and exits as told."""
    bin_dir = Path(tmp) / "bin"
    bin_dir.mkdir()
    log = Path(tmp) / "docker.log"
    stub = bin_dir / "docker"
    stub.write_text(f'#!/bin/sh\necho "$@" >> "{log}"\nexit {exit_code}\n', encoding="utf-8")
    stub.chmod(stub.stat().st_mode | stat.S_IXUSR)
    return bin_dir, log


def _assert_only_rebuildable_gone(root):
    for rel in REBUILDABLE:
        assert not (root / rel).exists(), f"not removed: {rel}"
    assert not (root / "_system/apps/dashboard/.venv").exists()
    for rel in KEPT:
        assert (root / rel).exists(), f"removed, but must stay: {rel}"


def test_removes_rebuildable_and_keeps_everything_else():
    with tempfile.TemporaryDirectory() as tmp:
        root = _vault(tmp)
        bin_dir, log = _stub_docker(tmp, 0)
        env = {**os.environ, "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"}
        subprocess.run(["make", "-C", str(root), "clean"], env=env, check=True, capture_output=True)
        _assert_only_rebuildable_gone(root)
        called = log.read_text(encoding="utf-8")
        assert "compose" in called and "down --rmi local" in called, called
        # never the volumes or every image: this wiki's own container and image only
        assert "--volumes" not in called and "--rmi all" not in called, called


def test_docker_daemon_down_still_cleans_files_and_says_so():
    with tempfile.TemporaryDirectory() as tmp:
        root = _vault(tmp)
        bin_dir, _ = _stub_docker(tmp, 1)
        env = {**os.environ, "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"}
        run = subprocess.run(["bash", str(root / "dashboard.sh"), "clean"], env=env,
                             capture_output=True, text=True)
        assert run.returncode == 0, run.stderr
        _assert_only_rebuildable_gone(root)
        assert "left in place" in run.stdout + run.stderr, run.stdout + run.stderr


def test_docker_not_installed_still_cleans_files_and_says_so():
    path = "/usr/bin:/bin"
    if shutil.which("docker", path=path):
        print("skip: docker sits on the minimal PATH")
        return
    with tempfile.TemporaryDirectory() as tmp:
        root = _vault(tmp)
        run = subprocess.run(["bash", str(root / "dashboard.sh"), "clean"],
                             env={**os.environ, "PATH": path}, capture_output=True, text=True)
        assert run.returncode == 0, run.stderr
        _assert_only_rebuildable_gone(root)
        assert "left in place" in run.stdout + run.stderr, run.stdout + run.stderr


def test_other_commands_still_need_docker():
    path = "/usr/bin:/bin"
    if shutil.which("docker", path=path):
        print("skip: docker sits on the minimal PATH")
        return
    with tempfile.TemporaryDirectory() as tmp:
        root = _vault(tmp)
        run = subprocess.run(["bash", str(root / "dashboard.sh"), "down"],
                             env={**os.environ, "PATH": path}, capture_output=True, text=True)
        assert run.returncode == 1, run.returncode
        assert "not installed" in run.stderr, run.stderr


def test_clean_twice_is_fine():
    with tempfile.TemporaryDirectory() as tmp:
        root = _vault(tmp)
        bin_dir, _ = _stub_docker(tmp, 0)
        env = {**os.environ, "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"}
        for _ in range(2):
            subprocess.run(["make", "-C", str(root), "clean"], env=env, check=True, capture_output=True)
        _assert_only_rebuildable_gone(root)


def test_help_lists_clean():
    out = subprocess.run(["make", "-C", str(_REPO), "help"], check=True, capture_output=True, text=True).stdout
    assert "make clean" in out, out


if __name__ == "__main__":
    test_removes_rebuildable_and_keeps_everything_else()
    test_docker_daemon_down_still_cleans_files_and_says_so()
    test_docker_not_installed_still_cleans_files_and_says_so()
    test_other_commands_still_need_docker()
    test_clean_twice_is_fine()
    test_help_lists_clean()
    print("OK: make clean")
