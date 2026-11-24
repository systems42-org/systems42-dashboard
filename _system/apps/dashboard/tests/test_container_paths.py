"""The dashboard starts inside its container. No pytest.

In the image the code sits at /app, so a path worked out from the code's own
place (`Path(__file__).parents[2]`) does not exist there. Every folder the app
reads outside /app must come from an environment variable that the Dockerfile
sets. Since FR-042 that is one variable, REPO_DIR, and every folder is found
below it. Regression: the anchors folder (FR-035) had no variable and no
mount, so the container stopped at import with IndexError.

Run from the dashboard dir:
    .venv/bin/python tests/test_container_paths.py
"""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
DOCKERFILE = (HERE / "Dockerfile").read_text(encoding="utf-8")
SCRIPT = (HERE.parents[2] / "dashboard.sh").read_text(encoding="utf-8")


def test_the_image_names_one_folder_and_the_launcher_mounts_it():
    """One mount (FR-042): the image sets REPO_DIR and no other folder
    variable, and the launcher mounts the repository there, read-only. The settings
    file of releases up to 0.11.4 is mounted only where a wiki still has one."""
    dirs = dict(re.findall(r"\b([A-Z_]+_DIR)=(/\S+)", DOCKERFILE))
    assert dirs == {"REPO_DIR": "/repo"}, dirs
    mounts = re.findall(r'-v "([^"]+)"', SCRIPT)
    assert mounts == ["$ROOT:/repo:ro", "$settings"], mounts


def test_every_folder_is_found_below_the_repository():
    """As in the image: only REPO_DIR is set. The app must not work a path
    out from its own place, which is /app there."""
    tmp = Path(tempfile.mkdtemp())
    env = {k: v for k, v in os.environ.items()
           if k not in ("WIKI_DIR", "RAW_SOURCES_DIR", "DOCS_DIR", "METAMODEL_DIR", "ANCHORS_DIR",
                        "WIKI_CONFIG")}
    env["REPO_DIR"] = str(tmp)
    code = ("import app, metamodel, wiki\n"
            "for p in (wiki.WIKI_DIR, wiki.SOURCES_DIR, app.DOCS_DIR, wiki.CONFIG_PATH,"
            " metamodel.METAMODEL_DIR, metamodel.ANCHORS_DIR): print(p)")
    out = subprocess.run([sys.executable, "-c", code], cwd=HERE, env=env, capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    want = ["wiki", "raw/sources", "docs", "_system/wiki.yaml",
            "_system/metamodel", "_system/anchors"]
    assert out.stdout.split() == [str(tmp / w) for w in want], out.stdout


def test_the_image_holds_every_module_the_app_imports():
    """A module next to app.py that the Dockerfile does not copy stops the container at import."""
    for mod in ("app.py", "catalog.py", "inputs.py", "metamodel.py", "wiki.py", "links.py", "render.py", "preflight.py", "gunicorn.conf.py"):
        assert re.search(r"^COPY " + re.escape(mod) + r" \.$", DOCKERFILE, re.M), mod


def test_metamodel_imports_from_a_shallow_place():
    """As in the image: the module at /app/metamodel.py, METAMODEL_DIR set,
    ANCHORS_DIR not set. The import must not fail, and the anchors sit next
    to the metamodel folder."""
    tmp = Path(tempfile.mkdtemp())
    app_dir = tmp / "app"
    app_dir.mkdir()
    for mod in ("metamodel.py", "inputs.py"):        # inputs.py: metamodel.py imports it
        (app_dir / mod).write_text((HERE / mod).read_text(encoding="utf-8"), encoding="utf-8")
    env = {k: v for k, v in os.environ.items() if k != "ANCHORS_DIR"}
    env["METAMODEL_DIR"] = str(tmp / "metamodel")
    out = subprocess.run(
        [sys.executable, "-c", "import metamodel; print(metamodel.ANCHORS_DIR)"],
        cwd=app_dir, env=env, capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    assert out.stdout.strip() == str(tmp / "anchors"), out.stdout


def test_up_reports_a_container_that_did_not_start():
    up = re.search(r"\n  up\)\n(.*?)\n    ;;", SCRIPT, re.S).group(1)
    assert "wait_for_dashboard" in up and "docker logs" in up and "exit 1" in up, up


def test_the_build_is_pinned_and_does_not_run_as_root():
    """Issue #34: the same Dockerfile builds the same image next month, and
    the dashboard has no root rights inside its container."""
    lines = [l.strip() for l in (HERE / "requirements.txt").read_text(encoding="utf-8").splitlines()]
    pins = dict(l.split("==") for l in lines if l and not l.startswith("#"))
    assert all(re.fullmatch(r"\d+(\.\d+)+", v) for v in pins.values()), pins
    # Flask's own dependencies are named too, not left to the day of the build
    for lib in ("Flask", "Werkzeug", "Jinja2", "MarkupSafe", "itsdangerous", "click", "blinker"):
        assert lib in pins, lib
    froms = re.findall(r"^FROM (\S+)", DOCKERFILE, re.M)
    assert re.fullmatch(r"python:[\d.]+-slim@sha256:[0-9a-f]{64}", froms[0]), froms
    assert set(froms[1:]) == {"base"}, froms          # the other stages build on it
    shipped = DOCKERFILE.rsplit("\nFROM base\n", 1)[1]
    user = re.search(r"^USER (\S+)", shipped, re.M)
    assert user and user.group(1) not in ("root", "0"), "the shipped stage names a user who is not root"
    assert '--user "$(id -u):$(id -g)"' in SCRIPT


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("ok")
