"""The start with uv (FR-054). No pytest.

Builds the wheel from this folder, checks that it holds what the container
image holds, and starts it with the real launcher in a throwaway wiki.

Needs `uv` and, for the first run, network to fetch the build tool and the
libraries. Without uv the test prints SKIP and exits 77, which
tests/run-all.sh counts as skipped.

Run from the dashboard dir:
    .venv/bin/python tests/test_uv_start.py
"""
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
_REPO = HERE.parents[2]
VERSION = (HERE / "VERSION").read_text(encoding="utf-8").strip()

if not shutil.which("uv"):
    print("SKIP: uv is not installed")
    sys.exit(77)


def _build(tmp):
    out = Path(tmp) / "dist"
    run = subprocess.run(["uv", "build", "--quiet", "--wheel", "--out-dir", str(out), str(HERE)],
                         capture_output=True, text=True)
    assert run.returncode == 0, run.stderr
    wheels = list(out.glob("*.whl"))
    assert [w.name for w in wheels] == [f"systems42_dashboard-{VERSION}-py3-none-any.whl"], wheels
    return wheels[0]


def _image_files():
    """What the last stage of the Dockerfile copies, as files relative to here."""
    last_stage = (HERE / "Dockerfile").read_text(encoding="utf-8").rsplit("\nFROM ", 1)[1]
    files = set()
    for src in re.findall(r"^COPY (\S+) ", last_stage, re.MULTILINE):
        path = HERE / src
        found = [f for f in path.rglob("*") if f.is_file()] if path.is_dir() else [path]
        files |= {f.relative_to(HERE).as_posix() for f in found
                  if "__pycache__" not in f.parts and f.name != ".DS_Store"}
    return files


def test_the_wheel_holds_what_the_image_holds(wheel):
    prefix = "systems42_dashboard/"
    names = zipfile.ZipFile(wheel).namelist()
    in_wheel = {n[len(prefix):] for n in names if n.startswith(prefix)} - {"__init__.py"}
    in_image = _image_files()
    assert in_image, "found no COPY lines in the Dockerfile"
    assert in_wheel == in_image, (
        f"only in the image: {sorted(in_image - in_wheel)}, only in the wheel: {sorted(in_wheel - in_image)}. "
        "Keep the COPY lines of the Dockerfile and force-include in pyproject.toml alike.")
    assert prefix + "__init__.py" in names


def _free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def test_the_launcher_serves_a_wiki_from_the_wheel(wheel, tmp):
    root = Path(tmp) / "mywiki"
    (root / "wiki").mkdir(parents=True)
    (root / "raw").mkdir()
    for folder in ("metamodel", "anchors"):
        shutil.copytree(_REPO / "_system" / folder, root / "_system" / folder)
    (root / "_system" / "wiki.yaml").write_text(
        f'system_name: "Wheel Test"\ndashboard_version: "{VERSION}"\n', encoding="utf-8")
    shutil.copy(_REPO / "dashboard.sh", root / "dashboard.sh")
    port = _free_port()
    env = {**os.environ, "DASH_WHEEL": str(wheel), "DASH_PORT": str(port), "DASH_NO_BROWSER": "1"}
    env.pop("REPO_DIR", None)
    server = subprocess.Popen(["bash", str(root / "dashboard.sh"), "uv"], env=env, start_new_session=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        page = None
        for _ in range(240):  # the first run installs the libraries
            if server.poll() is not None:
                break
            try:
                page = urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=2).read().decode("utf-8")
                break
            except OSError:
                time.sleep(0.5)
        assert page is not None, "the dashboard did not answer:\n" + (server.stdout.read() if server.poll() is not None else "")
        assert "Wheel Test" in page, "the home page does not show the wiki's name"
        assert VERSION in page, "the home page does not show the release"
        css = urllib.request.urlopen(f"http://127.0.0.1:{port}/static/style.css", timeout=2)
        assert css.status == 200
    finally:
        if server.poll() is None:
            os.killpg(server.pid, signal.SIGTERM)
        server.wait(timeout=20)


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as tmp:
        wheel = _build(tmp)
        test_the_wheel_holds_what_the_image_holds(wheel)
        test_the_launcher_serves_a_wiki_from_the_wheel(wheel, tmp)
    print("OK: uv start")
