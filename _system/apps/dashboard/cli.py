"""Start the dashboard without a container (FR-054).

    systems42-dashboard [WIKI]     serve the wiki in WIKI
    systems42-dashboard --version

`./dashboard.sh uv` runs this through uv. WIKI defaults to REPO_DIR, then to
the current folder. DASH_PORT sets the port (8080).

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
