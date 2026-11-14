"""The dashboard starts inside its container. No pytest.

In the image the code sits at /app, so a path worked out from the code's own
place (`Path(__file__).parents[2]`) does not exist there. Every folder the app
reads outside /app must come from an environment variable that the Dockerfile
sets and that compose mounts. Regression: the anchors folder (FR-035) had no
variable and no mount, so the container stopped at import with IndexError.

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
COMPOSE = (HERE / "compose.yaml").read_text(encoding="utf-8")
SCRIPT = (HERE.parents[2] / "dashboard.sh").read_text(encoding="utf-8")


def _env_dirs():
    return dict(re.findall(r"\b([A-Z_]+_DIR)=(/\S+?)(?:\s|\\|$)", DOCKERFILE))


def test_every_container_folder_is_mounted():
    dirs = _env_dirs()
    assert "ANCHORS_DIR" in dirs, dirs
    for name, path in dirs.items():
        assert re.search(r":" + re.escape(path) + r"(:ro)?\"", COMPOSE), (name, path)


def test_dashboard_sh_exports_the_anchors_folder():
    assert re.search(r'export ANCHORS_DIR="\$ROOT/_system/anchors"', SCRIPT)
    local = re.search(r"export WIKI_DIR SOURCES_DIR[^\n]*", SCRIPT).group(0)
    assert "ANCHORS_DIR" in local, local


def test_metamodel_imports_from_a_shallow_place():
    """As in the image: the module at /app/metamodel.py, METAMODEL_DIR set,
    ANCHORS_DIR not set. The import must not fail, and the anchors sit next
    to the metamodel folder."""
    tmp = Path(tempfile.mkdtemp())
    app_dir = tmp / "app"
    app_dir.mkdir()
    (app_dir / "metamodel.py").write_text((HERE / "metamodel.py").read_text(encoding="utf-8"),
                                          encoding="utf-8")
    env = {k: v for k, v in os.environ.items() if k != "ANCHORS_DIR"}
    env["METAMODEL_DIR"] = str(tmp / "metamodel")
    out = subprocess.run(
        [sys.executable, "-c", "import metamodel; print(metamodel.ANCHORS_DIR)"],
        cwd=app_dir, env=env, capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    assert out.stdout.strip() == str(tmp / "anchors"), out.stdout


def test_up_reports_a_container_that_did_not_start():
    up = re.search(r"\n  up\)\n(.*?)\n    ;;", SCRIPT, re.S).group(1)
    assert "report_failed_start" in up, up
    body = re.search(r"report_failed_start\(\) \{(.*?)\n\}", SCRIPT, re.S).group(1)
    assert "logs" in body and "exit 1" in body, body


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("ok")
