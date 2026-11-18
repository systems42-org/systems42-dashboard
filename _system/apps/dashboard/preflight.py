"""Is this a Systems42 wiki? (CON-005)

The dashboard works on Systems42 derivatives only. Before it starts, it checks
that the repository holds what it reads by convention. If something is
missing it says what, and stops. It does not guess.

No Flask import here: gunicorn.conf.py calls this before the app is loaded.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

# What a Systems42 derivative holds, relative to the repository root.
REQUIRED = ("wiki/", "raw/", "_system/wiki.yaml", "_system/metamodel/", "_system/anchors/")


def missing(repo: Path) -> list[str]:
    """The required parts `repo` lacks, in the order of REQUIRED."""
    out = []
    for rel in REQUIRED:
        p = repo / rel
        if not (p.is_dir() if rel.endswith("/") else p.is_file()):
            out.append(rel)
    return out


def message(repo: Path, parts: list[str]) -> str:
    return ("This is not a Systems42 wiki, so the dashboard cannot show it.\n"
            f"Missing in {repo}: " + ", ".join(parts) + ".\n"
            "Start the dashboard from the root of a repository created from Systems42.")


def stop_if_not_a_systems42_wiki() -> None:
    """Only with REPO_DIR set, which is how the image and the launcher run
    the dashboard. Tests and local runs name their folders one by one."""
    repo = os.environ.get("REPO_DIR")
    if not repo:
        return
    parts = missing(Path(repo))
    if parts:
        sys.exit(message(Path(repo), parts))
