"""The start with uv (FR-054). No pytest.

Builds the wheel from this folder, checks that it holds what the container
image holds, and starts it with the real launcher in a throwaway wiki.

Needs `uv` and, for the first run, network to fetch the build tool and the
libraries. Without uv the test prints SKIP and exits 77, which
tests/run-all.sh counts as skipped.

Run from the dashboard dir:
    .venv/bin/python tests/test_uv_start.py
"""
import functools
import http.server
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
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


def test_relative_path_settings_keep_the_folder_they_were_given_in(tmp):
    """cli.py changes into its own folder before gunicorn starts. A path
    setting such as WIKI_CONFIG=custom.yaml still means the file in the
    folder the launcher was started from."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("dashboard_cli", HERE / "cli.py")
    cli = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cli)
    start = Path(tmp).resolve()
    names = ("WIKI_DIR", "RAW_SOURCES_DIR", "WIKI_CONFIG", "DOCS_DIR",
             "METAMODEL_DIR", "NOTATIONS_DIR", "ANCHORS_DIR")
    saved = {k: os.environ.get(k) for k in (*names, "REPO_DIR", "PYTHONPATH")}
    saved_argv, saved_cwd, saved_execv = sys.argv, os.getcwd(), os.execv
    seen = {}
    try:
        for k in names:
            os.environ[k] = f"rel/{k.lower()}"
        os.environ["WIKI_CONFIG"] = "/abs/custom.yaml"
        # An absolute path through a symlink stays as given: metamodel.py
        # finds notations/ and anchors/ next to METAMODEL_DIR.
        (start / "shared" / "metamodel").mkdir(parents=True)
        (start / "schema").mkdir()
        (start / "schema" / "metamodel").symlink_to(start / "shared" / "metamodel")
        os.environ["METAMODEL_DIR"] = str(start / "schema" / "metamodel")
        os.chdir(start)
        sys.argv = ["systems42-dashboard", "."]
        os.execv = lambda *a: seen.update({k: os.environ[k] for k in names}, cwd=os.getcwd())
        cli.main()
    finally:
        os.execv, sys.argv = saved_execv, saved_argv
        os.chdir(saved_cwd)
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    assert Path(seen["cwd"]).resolve() == HERE, seen["cwd"]
    for k in names:
        if k not in ("WIKI_CONFIG", "METAMODEL_DIR"):
            assert seen[k] == str(start / "rel" / k.lower()), (k, seen[k])
    assert seen["WIKI_CONFIG"] == "/abs/custom.yaml", seen["WIKI_CONFIG"]
    assert seen["METAMODEL_DIR"] == str(start / "schema" / "metamodel"), seen["METAMODEL_DIR"]


def _free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _make_wiki(tmp):
    root = Path(tmp) / "mywiki"
    (root / "wiki").mkdir(parents=True)
    (root / "raw").mkdir()
    for folder in ("metamodel", "anchors"):
        shutil.copytree(_REPO / "_system" / folder, root / "_system" / folder)
    (root / "_system" / "wiki.yaml").write_text(
        f'system_name: "Wheel Test"\ndashboard_version: "{VERSION}"\n', encoding="utf-8")
    shutil.copy(_REPO / "dashboard.sh", root / "dashboard.sh")
    # Modules that share a name with the dashboard's own, in the folder the
    # launcher is started from. The dashboard must load its own.
    for name in ("app.py", "preflight.py"):
        (root / name).write_text(f'raise SystemExit("loaded {name} from the wiki folder")\n', encoding="utf-8")
    return root


def _serve(root, wheel, **extra_env):
    """Start `./dashboard.sh uv` from the wiki folder, check the home page,
    stop it."""
    port = _free_port()
    env = {**os.environ, "DASH_WHEEL": str(wheel), "DASH_PORT": str(port), "DASH_NO_BROWSER": "1", **extra_env}
    env.pop("REPO_DIR", None)
    server = subprocess.Popen(["bash", str(root / "dashboard.sh"), "uv"], cwd=root, env=env, start_new_session=True,
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


def _wheel_server(wheel):
    """Serve the wheel's folder over HTTP, as the GitHub release serves it.
    Returns the server and the wheel's address."""
    class Quiet(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass

    handler = functools.partial(Quiet, directory=str(wheel.parent))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, f"http://127.0.0.1:{server.server_address[1]}/{wheel.name}"


def test_the_launcher_serves_a_wiki_from_the_wheel(wheel, tmp):
    """The first start fetches the wheel by its address, as from a release."""
    root = _make_wiki(tmp)
    server, url = _wheel_server(wheel)
    try:
        _serve(root, url)
    finally:
        server.shutdown()
        server.server_close()
    return root, url


def test_a_release_started_once_starts_again_without_network(root, url):
    """FR-054: the second start needs no network. The address it was fetched
    from is gone, and UV_OFFLINE keeps every uv call in the launcher, the
    fallback fetch too, to uv's cache."""
    _serve(root, url, UV_OFFLINE="1")


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as tmp:
        wheel = _build(tmp)
        test_the_wheel_holds_what_the_image_holds(wheel)
        test_relative_path_settings_keep_the_folder_they_were_given_in(tmp)
        root, url = test_the_launcher_serves_a_wiki_from_the_wheel(wheel, tmp)
        test_a_release_started_once_starts_again_without_network(root, url)
    print("OK: uv start")
