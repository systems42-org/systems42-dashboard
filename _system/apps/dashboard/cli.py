"""Start the dashboard without a container (FR-054).

    systems42-dashboard [WIKI]     serve the wiki in WIKI
    systems42-dashboard --version

`./dashboard.sh uv` runs this through uv. WIKI defaults to REPO_DIR, then to
the current folder. DASH_PORT sets the port (8080). DASH_NO_SHUTDOWN=1 keeps
the dashboard running after the last browser tab has closed (FR-050).

In the wheel this file is the package `systems42_dashboard` (pyproject.toml),
and the dashboard's modules and files sit next to it, as they do here. The
modules import each other by their plain names (`import catalog`), so this
folder goes on the Python path.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
# Path settings that settings.py, wiki.py and metamodel.py read from the environment.
PATH_SETTINGS = ("WIKI_DIR", "RAW_SOURCES_DIR", "WIKI_CONFIG", "DOCS_DIR",
                 "METAMODEL_DIR", "NOTATIONS_DIR", "ANCHORS_DIR")


def main() -> None:
    args = sys.argv[1:]
    if args[:1] == ["--version"]:
        print((HERE / "VERSION").read_text(encoding="utf-8").strip())
        return
    if len(args) > 1 or args[:1] in (["-h"], ["--help"]):
        sys.exit("Usage: systems42-dashboard [WIKI] | --version")
    repo = Path(args[0] if args else os.environ.get("REPO_DIR") or ".").resolve()
    os.environ["REPO_DIR"] = str(repo)
    port = os.environ.get("DASH_PORT") or "8080"
    # In the environment, not as --pythonpath: gunicorn reads its config file,
    # which imports preflight, before it applies that option.
    os.environ["PYTHONPATH"] = os.pathsep.join(
        p for p in (str(HERE), os.environ.get("PYTHONPATH")) if p)
    # `python -m` puts the current folder first on the Python path, ahead of
    # PYTHONPATH. Started from the wiki, an app.py or preflight.py there would
    # replace the dashboard's own. So the server starts in this folder. The
    # wiki's path is resolved above. A relative path setting gets the folder it
    # was given in put in front. It is not resolved, so a symlink stays as
    # given: metamodel.py finds notations/ and anchors/ next to METAMODEL_DIR.
    start = os.getcwd()
    for name in PATH_SETTINGS:
        value = os.environ.get(name)
        if value and not os.path.isabs(value):
            os.environ[name] = os.path.join(start, value)
    os.chdir(HERE)
    # The server and its settings are those of the container image (Dockerfile).
    # gunicorn.conf.py stops with a message when WIKI is no Systems42 wiki.
    os.execv(sys.executable, [
        sys.executable, "-m", "gunicorn",
        "--config", str(HERE / "gunicorn.conf.py"),
        "--bind", f"0.0.0.0:{port}",
        "--worker-class", "gthread", "--workers", "1", "--threads", "4",
        "--no-control-socket",
        "app:app",
    ])


if __name__ == "__main__":
    main()
