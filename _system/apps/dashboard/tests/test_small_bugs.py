"""Eight small bugs from issue #59. No pytest.

1. /goals without a vision page still shows the objective cards and the matrix.
2. `*emphasis*` in a quality scenario touches text only, never a tag.
3. settings.js posts the client id the heartbeat uses, also when storage is blocked.
4. "Disconnect all" counts the other clients, not the facilitator's own tab.
5. /req42/<slug> is a 404 for the arc42 sections.
6. A metamodel route link is a same-site path only.
7. /issues?section= ignores case.
8. dashboard.sh names the container per wiki path (see also test_launcher.py).

Run from the dashboard dir:
    .venv/bin/python tests/test_small_bugs.py
"""
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in ("goals", "functional-requirements", "quality-requirements", "constraints", "issues"):
    (_wiki / _f).mkdir(parents=True)
(_tmp / "sources").mkdir()
(_tmp / "wiki.yaml").write_text("system_name: System X\n", encoding="utf-8")
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
_DASH = Path(__file__).resolve().parent.parent
_REPO = _DASH.parents[2]
sys.path.insert(0, str(_DASH))


def _page(folder, stem, title, status="draft", body="", **fields):
    pid = "-".join(stem.split("-")[:2])
    extra = "".join(f"{k}: {v}\n" for k, v in fields.items())
    (_wiki / folder / f"{stem}.md").write_text(
        f"---\nid: {pid}\ntitle: {title}\nstatus: {status}\nsources: []\n{extra}---\n\n# {title}\n\n{body}",
        encoding="utf-8")


# no vision page: two objectives, one served by an epic
_page("goals", "GOAL-002-served", "Served goal", stereotype="objective", related="[]")
_page("goals", "GOAL-003-unserved", "Unserved goal", stereotype="objective", related="[]")
_page("functional-requirements", "FR-001-epic", "An epic", notation="agile", level="epic",
      lane="backbone", parent="[]", goal='["[[GOAL-002-served]]"]', related="[]")
_page("constraints", "CON-001-small", "Small", related="[]")
_page("quality-requirements", "QR-001-fast", "Fast", related="[]", body=(
    "- **Source.** [[CON-001-small|foo*bar]] and *baz*\n"
    "- **Measure.** within *300 ms*\n"))
_page("issues", "ISS-001-about-con", "About the constraint", "open", related='["[[CON-001-small]]"]')
_page("issues", "ISS-002-about-qr", "About the QR", "open", related='["[[QR-001-fast]]"]')

import app  # noqa: E402
import render  # noqa: E402
import project.requirements  # noqa: E402

client = app.app.test_client()


def test_goals_without_a_vision_show_objectives_and_matrix():
    r = client.get("/goals")
    assert r.status_code == 200, r.status_code
    body = r.get_data(as_text=True)
    assert "No vision yet" in body
    for gid in ("GOAL-002", "GOAL-003"):
        assert f'<section id="{gid}" class="goal-card">' in body, gid
    assert "Goal coverage matrix" in body
    assert 'data-goal="GOAL-002"' in body and 'data-goal="GOAL-003"' in body
    assert "FR-001" in body


def test_emphasis_never_touches_a_tag_or_an_attribute():
    html = '<a href="/x*y" title="a*b">foo*bar</a> and *baz*'
    out = project.requirements._emphasis(html)
    assert out == '<a href="/x*y" title="a*b">foo*bar</a> and <em>baz</em>', out
    clean = render.sanitize_html('<a href="/page/x">foo*bar</a> and *baz*')
    out = project.requirements._emphasis(clean)
    assert out.endswith("foo*bar</a> and <em>baz</em>"), out
    assert render.sanitize_html(out) == out, out


def test_quality_block_keeps_links_whole():
    body = client.get("/req42/quality").get_data(as_text=True)
    assert "foo*bar</a> and <em>baz</em>" in body, body
    assert "within <em>300 ms</em>" in body


def test_settings_uses_the_heartbeat_client_id():
    base = (_DASH / "templates" / "base.html").read_text(encoding="utf-8")
    js = (_DASH / "static" / "settings.js").read_text(encoding="utf-8")
    assert "window.etsuClientId = CLIENT_ID;" in base
    m = re.search(r"function clientId\(\) \{(.*?)\n  \}", js, re.S)
    assert m and m.group(1).lstrip().startswith("if (window.etsuClientId)"), m and m.group(1)


def _confirm_text(count):
    """Run the confirm text logic of base.html's disconnect button in node."""
    base = (_DASH / "templates" / "base.html").read_text(encoding="utf-8")
    start = base.index("var others =")
    code = base[start:base.index("if (!window.confirm(ask))", start)]
    script = f'var presenceCountEl = {{textContent: "{count}"}};\n{code}\nprocess.stdout.write(ask);'
    return subprocess.run(["node", "-e", script], check=True, capture_output=True, text=True).stdout


def test_disconnect_all_counts_the_other_clients():
    if not shutil.which("node"):
        print("skip: node is not installed")
        return
    assert _confirm_text(1) == "Nobody else is connected. Stop the dashboard?"
    assert _confirm_text(2) == "Disconnect 1 other client and stop the dashboard?"
    assert _confirm_text(4) == "Disconnect 3 other clients and stop the dashboard?"


def test_req42_route_refuses_arc42_slugs():
    for slug in ("strategy", "building-blocks", "deployment", "runtime", "concepts"):
        assert client.get(f"/req42/{slug}").status_code == 404, slug
    for slug in ("quality", "constraints", "scope", "models"):
        assert client.get(f"/req42/{slug}").status_code == 200, slug


def test_metamodel_route_link_stays_on_the_site():
    for good in ("/goals", "/req42/quality", "/"):
        m = app._MM_ROUTE_RE.match(good)
        assert m and m.group(1) == good, good
    for raw, want in (
        ("/arc42/deployment, /page/deployment-nodes/<DN> (subtree)", "/arc42/deployment"),
        ("/goals (covering-epic counts)", "/goals"),
        ("/goals; /other", "/goals"),
    ):
        m = app._MM_ROUTE_RE.match(raw)
        assert m and m.group(1) == want, (raw, m.group(1) if m else None)
    for bad in ("//evil.example/x", "/\\evil.example/x", "https://evil.example/", "none"):
        assert not app._MM_ROUTE_RE.match(bad), bad


def test_issue_section_filter_ignores_case():
    def ids(q):
        return set(re.findall(r"ISS-00\d", client.get(f"/issues?section={q}").get_data(as_text=True)))
    assert ids("C2") == {"ISS-001"}, ids("C2")
    assert ids("c2") == {"ISS-001"}, ids("c2")


def _launcher_run(root, bin_dir, *args):
    env = {**os.environ, "PATH": f"{bin_dir}{os.pathsep}/usr/bin:/bin", "DASH_NO_BROWSER": "1"}
    env.pop("DASH_PORT", None)
    return subprocess.run(["bash", str(root / "dashboard.sh"), *args], env=env,
                          capture_output=True, text=True)


def _launcher_setup(tmp, legacy_owner=None):
    """Two wikis both in a folder named `wiki`, and a stub docker that logs its
    arguments. It says the old-named container mounts wiki `legacy_owner`
    (0 or 1), or a third wiki elsewhere."""
    roots = []
    for parent in ("a", "b"):
        root = Path(tmp) / parent / "wiki"
        (root / "_system").mkdir(parents=True)
        (root / "_system" / "wiki.yaml").write_text('dashboard_version: "0.9.0"\n', encoding="utf-8")
        shutil.copy(_REPO / "dashboard.sh", root / "dashboard.sh")
        roots.append(root)
    legacy_source = "/elsewhere/wiki" if legacy_owner is None else roots[legacy_owner]
    bin_dir = Path(tmp) / "bin"
    bin_dir.mkdir()
    log = Path(tmp) / "docker.log"
    stubs = {
        "docker": (f'#!/bin/sh\necho "$@" >> "{log}"\n'
                   'case "$1 $2" in\n'
                   '  "inspect -f")\n'
                   '    case "$*" in *systems42-dashboard-wiki) echo "' + str(legacy_source) + '";;\n'
                   '      *) echo true;; esac;;\n'
                   'esac\nexit 0\n'),
        "curl": "#!/bin/sh\nexit 0\n",
    }
    for name, text in stubs.items():
        f = bin_dir / name
        f.write_text(text, encoding="utf-8")
        f.chmod(f.stat().st_mode | stat.S_IXUSR)
    return roots, bin_dir, log


def _names(log, verb):
    return [l.split()[-1] for l in log.read_text(encoding="utf-8").splitlines() if l.startswith(verb)]


def test_launcher_names_the_container_per_wiki_path():
    with tempfile.TemporaryDirectory() as tmp:
        (a, b), bin_dir, log = _launcher_setup(tmp)
        for root in (a, b):
            assert _launcher_run(root, bin_dir).returncode == 0
        started = [l.split("--name ")[1].split()[0]
                   for l in log.read_text(encoding="utf-8").splitlines() if l.startswith("run ")]
        assert len(started) == 2 and started[0] != started[1], started
        for name in started:
            assert re.fullmatch(r"systems42-dashboard-wiki-[0-9a-f]{8}", name), name
        # the second start removed only its own container, never the first one's
        removed = _names(log, "rm -f")
        assert started[0] not in removed[1:], removed
        # the old name belongs to another wiki: left alone
        assert "systems42-dashboard-wiki" not in removed, removed
        # the name is stable across runs
        log.unlink()
        _launcher_run(a, bin_dir, "down")
        assert _names(log, "rm -f") == [started[0]], log.read_text(encoding="utf-8")


def test_launcher_removes_its_own_container_under_the_old_name():
    """After an upgrade the old-named container of this wiki is no orphan:
    down, clean and a new start remove it."""
    for cmd in ("down", "clean", "up"):
        with tempfile.TemporaryDirectory() as tmp:
            (a, _), bin_dir, log = _launcher_setup(tmp, legacy_owner=0)
            assert _launcher_run(a, bin_dir, cmd).returncode == 0, cmd
            assert "systems42-dashboard-wiki" in _names(log, "rm -f"), (cmd, log.read_text(encoding="utf-8"))


def test_launcher_follows_the_log_of_the_old_container():
    with tempfile.TemporaryDirectory() as tmp:
        (a, _), bin_dir, log = _launcher_setup(tmp, legacy_owner=0)
        # `docker inspect NAME` fails: no container under the new name yet
        stub = bin_dir / "docker"
        text = stub.read_text(encoding="utf-8")
        stub.write_text(text.replace(
            "esac\nexit 0\n", '  "inspect systems42-dashboard-wiki-"*) exit 1;;\nesac\nexit 0\n'),
            encoding="utf-8")
        assert _launcher_run(a, bin_dir, "logs").returncode == 0
        assert _names(log, "logs -f") == ["systems42-dashboard-wiki"], log.read_text(encoding="utf-8")


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("OK: small bugs")
