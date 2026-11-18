"""The dashboard works on Systems42 wikis only (CON-005). No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_preflight.py
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))
import preflight  # noqa: E402


def _wiki(tmp, leave_out=()):
    root = Path(tmp)
    for rel in preflight.REQUIRED:
        if rel in leave_out:
            continue
        p = root / rel
        if rel.endswith("/"):
            p.mkdir(parents=True)
        else:
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("system_name: x\n", encoding="utf-8")
    return root


def test_a_complete_wiki_lacks_nothing():
    with tempfile.TemporaryDirectory() as tmp:
        assert preflight.missing(_wiki(tmp)) == []


def test_every_missing_part_is_named():
    with tempfile.TemporaryDirectory() as tmp:
        root = _wiki(tmp, leave_out=("raw/", "_system/metamodel/"))
        assert preflight.missing(root) == ["raw/", "_system/metamodel/"]
        text = preflight.message(root, preflight.missing(root))
        assert "raw/, _system/metamodel/" in text and "not a Systems42 wiki" in text, text


def test_a_file_where_a_folder_belongs_counts_as_missing():
    with tempfile.TemporaryDirectory() as tmp:
        root = _wiki(tmp, leave_out=("wiki/",))
        (root / "wiki").write_text("x", encoding="utf-8")
        assert preflight.missing(root) == ["wiki/"]


def _run(env_extra):
    env = {k: v for k, v in os.environ.items() if k != "REPO_DIR"}
    env.update(env_extra)
    return subprocess.run([sys.executable, "-c", "import preflight; preflight.stop_if_not_a_systems42_wiki()"],
                          cwd=HERE, env=env, capture_output=True, text=True)


def test_it_stops_and_says_what_is_missing():
    with tempfile.TemporaryDirectory() as tmp:
        root = _wiki(tmp, leave_out=("_system/anchors/",))
        run = _run({"REPO_DIR": str(root)})
        assert run.returncode == 1, run.returncode
        assert "_system/anchors/" in run.stderr, run.stderr


def test_it_lets_a_complete_wiki_start():
    with tempfile.TemporaryDirectory() as tmp:
        assert _run({"REPO_DIR": str(_wiki(tmp))}).returncode == 0


def test_without_repo_dir_it_checks_nothing():
    """Tests and local runs name their folders one by one."""
    assert _run({}).returncode == 0


def test_gunicorn_runs_the_check_before_any_worker():
    conf = (HERE / "gunicorn.conf.py").read_text(encoding="utf-8")
    assert "def on_starting(server)" in conf and "stop_if_not_a_systems42_wiki()" in conf, conf


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("OK: preflight")
