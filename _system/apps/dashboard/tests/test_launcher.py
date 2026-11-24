"""The launcher, dashboard.sh (FR-042). No pytest.

Runs the real script in a throwaway wiki with stub `docker`, `curl` and
`open` on PATH: no container is started and no network is used.

Run from the dashboard dir:
    .venv/bin/python tests/test_launcher.py
"""
import os
import stat
import subprocess
import tempfile
from pathlib import Path

_REPO = Path(__file__).resolve().parents[4]
LAUNCHER = _REPO / "dashboard.sh"


def _wiki(tmp, yaml):
    root = Path(tmp) / "mywiki"
    (root / "_system").mkdir(parents=True)
    (root / "_system" / "wiki.yaml").write_text(yaml, encoding="utf-8")
    (root / "dashboard.sh").write_text(LAUNCHER.read_text(encoding="utf-8"), encoding="utf-8")
    return root


def _stubs(tmp, release_json='{"tag_name": "v1.2.0", "name": "1.2.0"}'):
    """`docker` logs its arguments and says the container runs. `curl` answers
    the release question and every other request with success."""
    bin_dir = Path(tmp) / "bin"
    bin_dir.mkdir()
    log = Path(tmp) / "docker.log"
    scripts = {
        "docker": f'#!/bin/sh\necho "$@" >> "{log}"\ncase "$1" in inspect) echo true;; esac\nexit 0\n',
        "curl": f"#!/bin/sh\ncase \"$*\" in *releases/latest*) echo '{release_json}';; esac\nexit 0\n",
        "open": "#!/bin/sh\nexit 0\n",
    }
    for name, body in scripts.items():
        f = bin_dir / name
        f.write_text(body, encoding="utf-8")
        f.chmod(f.stat().st_mode | stat.S_IXUSR)
    return bin_dir, log


def _run(root, bin_dir, *args):
    env = {**os.environ, "PATH": f"{bin_dir}{os.pathsep}/usr/bin:/bin", "DASH_NO_BROWSER": "1"}
    env.pop("DASH_PORT", None)
    env.pop("DASH_PUBLIC_URL", None)
    return subprocess.run(["bash", str(root / "dashboard.sh"), *args], env=env, capture_output=True, text=True)


def test_it_starts_the_release_the_wiki_names_with_one_mount():
    with tempfile.TemporaryDirectory() as tmp:
        root = _wiki(tmp, 'system_name: "X"\ndashboard_version: "0.9.0"  # quoted\n')
        bin_dir, log = _stubs(tmp)
        run = _run(root, bin_dir)
        assert run.returncode == 0, run.stderr
        called = log.read_text(encoding="utf-8")
        start = [l for l in called.splitlines() if l.startswith("run ")]
        assert len(start) == 1, called
        assert start[0].endswith("ghcr.io/systems42-org/dashboard:0.9.0"), start[0]
        assert f"-v {root}:/repo:ro" in start[0], start[0]
        assert start[0].count(" -v ") == 1, start[0]
        assert f"--user {os.getuid()}:{os.getgid()}" in start[0], "the container must not run as root"
        assert "--name systems42-dashboard-mywiki" in start[0], start[0]
        assert "build" not in called, called
        # the dashboard writes nothing, so the launcher creates no settings file (FR-046)
        assert not (root / "_system" / "dashboard.yaml").exists()
        assert "Dashboard 0.9.0 running" in run.stdout, run.stdout


def test_a_settings_file_of_an_older_release_is_still_mounted():
    """Releases up to 0.11.4 save the view in _system/dashboard.yaml. A wiki
    that still has the file can keep running them."""
    with tempfile.TemporaryDirectory() as tmp:
        root = _wiki(tmp, 'system_name: "X"\ndashboard_version: "0.9.0"\n')
        (root / "_system" / "dashboard.yaml").write_text("hidden: []\n", encoding="utf-8")
        bin_dir, log = _stubs(tmp)
        run = _run(root, bin_dir)
        assert run.returncode == 0, run.stderr
        start = [l for l in log.read_text(encoding="utf-8").splitlines() if l.startswith("run ")]
        assert f"-v {root}/_system/dashboard.yaml:/repo/_system/dashboard.yaml" in start[0], start[0]
        assert start[0].count(" -v ") == 2, start[0]


def test_dash_no_shutdown_reaches_the_container_only_when_set():
    """FR-050: the switch for the automatic stop is read inside the container,
    so the launcher has to hand it on."""
    for value, expected in ((None, False), ("1", True)):
        with tempfile.TemporaryDirectory() as tmp:
            root = _wiki(tmp, 'dashboard_version: "0.9.0"\n')
            bin_dir, log = _stubs(tmp)
            env = {**os.environ, "PATH": f"{bin_dir}{os.pathsep}/usr/bin:/bin", "DASH_NO_BROWSER": "1"}
            for key in ("DASH_PORT", "DASH_PUBLIC_URL", "DASH_NO_SHUTDOWN"):
                env.pop(key, None)
            if value is not None:
                env["DASH_NO_SHUTDOWN"] = value
            run = subprocess.run(["bash", str(root / "dashboard.sh")], env=env, capture_output=True, text=True)
            assert run.returncode == 0, run.stderr
            start = [l for l in log.read_text(encoding="utf-8").splitlines() if l.startswith("run ")]
            assert len(start) == 1, start
            assert ("-e DASH_NO_SHUTDOWN=1" in start[0]) is expected, start[0]
            assert ("DASH_NO_SHUTDOWN" in start[0]) is expected, start[0]
            assert start[0].endswith("ghcr.io/systems42-org/dashboard:0.9.0"), start[0]


def test_an_unquoted_version_is_read_too():
    with tempfile.TemporaryDirectory() as tmp:
        root = _wiki(tmp, "dashboard_version: 0.9.0\n")
        bin_dir, log = _stubs(tmp)
        assert _run(root, bin_dir).returncode == 0
        assert "ghcr.io/systems42-org/dashboard:0.9.0" in log.read_text(encoding="utf-8")


def test_a_wiki_that_names_no_release_is_told_what_to_do():
    with tempfile.TemporaryDirectory() as tmp:
        root = _wiki(tmp, 'system_name: "X"\n# dashboard_version: "0.9.0"\n')
        bin_dir, log = _stubs(tmp)
        run = _run(root, bin_dir)
        assert run.returncode == 1, run.returncode
        assert "names no dashboard release" in run.stderr and "update" in run.stderr, run.stderr
        assert not log.exists() or "run " not in log.read_text(encoding="utf-8")


def test_local_needs_the_dashboard_code():
    with tempfile.TemporaryDirectory() as tmp:
        root = _wiki(tmp, "dashboard_version: local\n")
        bin_dir, log = _stubs(tmp)
        run = _run(root, bin_dir)
        assert run.returncode == 1 and "_system/apps/dashboard" in run.stderr, run.stderr
        (root / "_system" / "apps" / "dashboard").mkdir(parents=True)
        (root / "_system" / "apps" / "dashboard" / "Dockerfile").write_text("FROM scratch\n", encoding="utf-8")
        run = _run(root, bin_dir)
        assert run.returncode == 0, run.stderr
        called = log.read_text(encoding="utf-8")
        assert "build -q -t systems42-dashboard:local" in called, called
        assert "ghcr.io" not in called, called


def _uv_run(yaml, uv_script='#!/bin/sh\necho "$@" >> "$UV_LOG"\nexit 0\n',
            curl_script="#!/bin/sh\nexit 7\n", **extra_env):
    """`./dashboard.sh uv` with a stub `uv` that logs its arguments, and a
    `curl` that finds nothing on the port (unless `curl_script` says
    otherwise). Returns the run, the uv log and the docker log."""
    with tempfile.TemporaryDirectory() as tmp:
        root = _wiki(tmp, yaml)
        bin_dir, docker_log = _stubs(tmp)
        (bin_dir / "curl").write_text(curl_script, encoding="utf-8")
        if uv_script:
            f = bin_dir / "uv"
            f.write_text(uv_script, encoding="utf-8")
            f.chmod(f.stat().st_mode | stat.S_IXUSR)
        uv_log = Path(tmp) / "uv.log"
        env = {**os.environ, "PATH": f"{bin_dir}{os.pathsep}/usr/bin:/bin", "DASH_NO_BROWSER": "1",
               "UV_LOG": str(uv_log), **extra_env}
        for key in ("DASH_PORT", "DASH_PUBLIC_URL"):
            env.pop(key, None)
        if "DASH_WHEEL" not in extra_env:
            env.pop("DASH_WHEEL", None)
        run = subprocess.run(["bash", str(root / "dashboard.sh"), "uv"], env=env, capture_output=True, text=True)
        called = uv_log.read_text(encoding="utf-8") if uv_log.exists() else ""
        return run, called, docker_log.exists()


def test_uv_starts_the_wheel_of_the_release_the_wiki_names():
    """FR-054: the same pin as the container start, and no Docker."""
    run, called, docker_used = _uv_run('dashboard_version: "0.13.0"\n')
    assert run.returncode == 0, run.stderr
    wheel = ("https://github.com/systems42-org/systems42-dashboard/releases/download/"
             "v0.13.0/systems42_dashboard-0.13.0-py3-none-any.whl")
    start = called.splitlines()[-1]
    assert start.startswith("tool run ") and start.endswith(f"--from {wheel} systems42-dashboard"), called
    assert "--offline" in start, "a release fetched before must start without network"
    assert not docker_used, "the uv start must not call docker"


def test_uv_takes_a_wheel_from_a_file():
    run, called, _ = _uv_run('dashboard_version: "0.13.0"\n', DASH_WHEEL="/tmp/some.whl")
    assert run.returncode == 0, run.stderr
    assert "--from /tmp/some.whl systems42-dashboard" in called and "github.com" not in called, called


def test_uv_missing_is_said():
    run, called, _ = _uv_run('dashboard_version: "0.13.0"\n', uv_script=None)
    assert run.returncode == 1 and "uv is not installed" in run.stderr, run.stderr


def test_uv_says_what_to_do_when_the_release_has_no_wheel():
    run, _, _ = _uv_run('dashboard_version: "0.9.0"\n', uv_script="#!/bin/sh\nexit 1\n")
    assert run.returncode == 1, run.returncode
    assert "could not fetch dashboard 0.9.0" in run.stderr and "update" in run.stderr, run.stderr


def test_uv_with_local_needs_the_dashboard_code():
    run, called, _ = _uv_run("dashboard_version: local\n")
    assert run.returncode == 1 and "_system/apps/dashboard" in run.stderr, run.stderr
    assert called == "", called


def test_uv_on_a_busy_port_says_how_to_stop_a_uv_start():
    """A machine that runs the uv start often has no Docker, so the hint
    must not name only ./dashboard.sh down."""
    run, called, _ = _uv_run('dashboard_version: "0.13.0"\n', curl_script="#!/bin/sh\nexit 0\n")
    assert run.returncode == 1 and "already in use" in run.stderr, run.stderr
    assert "Ctrl+C" in run.stderr, run.stderr
    assert "systems42-dashboard\n" not in called, "it must not start a second server"


def test_a_folder_that_is_no_wiki_is_refused():
    with tempfile.TemporaryDirectory() as tmp:
        root = _wiki(tmp, "")
        (root / "_system" / "wiki.yaml").unlink()
        bin_dir, _ = _stubs(tmp)
        run = _run(root, bin_dir)
        assert run.returncode == 1 and "not a Systems42 wiki" in run.stderr, run.stderr


def _updated(yaml):
    with tempfile.TemporaryDirectory() as tmp:
        root = _wiki(tmp, yaml)
        bin_dir, log = _stubs(tmp)
        run = _run(root, bin_dir, "update")
        assert run.returncode == 0, run.stderr
        assert not log.exists(), "update must not start anything"
        return (root / "_system" / "wiki.yaml").read_text(encoding="utf-8"), run.stdout


def test_update_names_the_newest_release():
    text, out = _updated('system_name: "X"\ndashboard_version: "0.9.0"  # old\nintro: on\n')
    lines = text.splitlines()
    assert lines[0] == 'system_name: "X"' and lines[2] == "intro: on", text
    assert lines[1].startswith('dashboard_version: "1.2.0"'), text
    assert "1.2.0" in out and "0.9.0" in out, out


def test_update_fills_in_a_commented_or_missing_line():
    text, _ = _updated('system_name: "X"\n# dashboard_version: "0.9.0"  # example\n')
    assert text.count("dashboard_version") == 1 and '\ndashboard_version: "1.2.0"' in text, text
    text, _ = _updated('system_name: "X"\n')
    assert text.startswith('system_name: "X"\n') and 'dashboard_version: "1.2.0"' in text, text


def test_update_leaves_a_current_wiki_alone():
    yaml = 'dashboard_version: "1.2.0"  # mine\n'
    text, out = _updated(yaml)
    assert text == yaml and "already" in out, (text, out)


def test_an_unknown_command_is_refused_where_no_dashboard_code_is():
    with tempfile.TemporaryDirectory() as tmp:
        root = _wiki(tmp, 'dashboard_version: "0.9.0"\n')
        bin_dir, _ = _stubs(tmp)
        run = _run(root, bin_dir, "test")
        assert run.returncode == 2 and "Usage" in run.stderr, run.stderr


def test_the_dashboard_repository_hands_other_commands_to_dev_sh():
    dev = (_REPO / "_system" / "apps" / "dashboard" / "dev.sh")
    assert os.access(dev, os.X_OK), "dev.sh must be executable"
    text = dev.read_text(encoding="utf-8")
    for cmd in ("rebuild)", "local)", "app-start)", "test)"):
        assert cmd in text, cmd


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("OK: launcher")
