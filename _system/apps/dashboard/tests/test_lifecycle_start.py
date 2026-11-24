"""The watchdog starts only where a server starts, and DASH_NO_SHUTDOWN
switches the automatic stop off (FR-050, issue #182).

`import app` used to start the watchdog thread. The site export and the tests
import app only for the Flask test client: past the startup grace the thread
sent SIGTERM to the process and to its parent, whatever that parent was.

Now a server entry point calls `session.start_lifecycle()`: the Gunicorn hook in
gunicorn.conf.py, which passes the master's pid, and `python app.py`. Only
that pid is ever signalled besides the process itself.

No test here signals its parent. In-process tests stub `session._shutdown`, the
child interpreters stub `os.kill`, and the Gunicorn test starts its own
Gunicorn, whose worker signals that Gunicorn's master.

Run from the dashboard dir:
    .venv/bin/python tests/test_lifecycle_start.py
"""
import json
import os
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent

WIKI_FOLDERS = [
    "domain-terms", "goals", "stakeholders", "context", "external-interfaces",
    "activity-models", "functional-requirements",
    "quality-requirements", "constraints", "issues",
]

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in WIKI_FOLDERS:
    (_wiki / _f).mkdir(parents=True)
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
# The default periods on purpose, and no DASH_STARTUP_GRACE=3600: nothing
# runs in this process that could act on them.
for _name in ("DASH_STARTUP_GRACE", "DASH_HEARTBEAT_GRACE", "DASH_LEAVE_GRACE",
              "DASH_NO_SHUTDOWN", "REPO_DIR"):
    os.environ.pop(_name, None)

sys.path.insert(0, str(HERE))  # import app.py

import app  # noqa: E402
import session  # noqa: E402

FAKE_MASTER = 4242  # never signalled: the children stub os.kill

# Runs in a child interpreter. os.kill records instead of sending. The body
# sets `result`, which goes back as one JSON line.
_PRELUDE = """
import importlib.util, json, os, signal, sys, threading, time
sys.path.insert(0, sys.argv[1])
import app
import session
kills = []
session.os.kill = lambda pid, sig: kills.append([pid, int(sig)])

def threads():
    return sorted(t.name for t in threading.enumerate())

def wait_for(done, seconds=6.0):
    end = time.monotonic() + seconds
    while not done() and time.monotonic() < end:
        time.sleep(0.05)

def gunicorn_conf():
    spec = importlib.util.spec_from_file_location(
        "gunicorn_conf", os.path.join(sys.argv[1], "gunicorn.conf.py"))
    conf = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(conf)
    return conf

class Worker:
    ppid = %d

def post(client, route, cid):
    return client.post(route, data=json.dumps({"client_id": cid}),
                       content_type="application/json").status_code
""" % FAKE_MASTER


def _child(body, **env):
    """Run `body` after the prelude in a fresh interpreter. Returns its
    `result` and its pid."""
    full_env = dict(os.environ, **env)
    run = subprocess.run(
        [sys.executable, "-c",
         _PRELUDE + body + "\nprint(json.dumps({'result': result, 'pid': os.getpid()}))",
         str(HERE)],
        capture_output=True, text=True, env=full_env, timeout=60)
    assert run.returncode == 0, run.stdout + run.stderr
    out = json.loads(run.stdout.strip().splitlines()[-1])
    return out["result"], out["pid"]


TERM = int(signal.SIGTERM)


def test_importing_app_starts_no_thread_and_stops_nothing():
    # A startup grace of 0.2 s and 2.5 s of work with the test client, pings
    # included: the old import-time watchdog (one pass a second) had signalled
    # twice by then.
    result, _ = _child("""
import catalog, inputs, metamodel
after_import = threads()
client = app.app.test_client()
statuses = [client.get("/").status_code, post(client, "/ping", "a"),
            post(client, "/leaving", "a")]
time.sleep(2.5)
statuses.append(client.get("/").status_code)
result = {"after_import": after_import, "after_work": threads(), "kills": kills,
          "statuses": statuses, "shutting_down": session._shutting_down,
          "started": session._watchdog_started}
""", DASH_STARTUP_GRACE="0.2", DASH_LEAVE_GRACE="0.2", DASH_HEARTBEAT_GRACE="0.2")
    assert result["after_import"] == ["MainThread"], result
    assert result["after_work"] == ["MainThread"], result
    assert result["statuses"] == [200, 200, 204, 200], result
    assert result["kills"] == [] and result["shutting_down"] is False, result
    assert result["started"] is False, result


def test_the_gunicorn_hook_starts_the_watchdog_and_only_its_master_is_stopped():
    # Normal operation, automatic stop on: no page ever connects, so the
    # startup grace ends the server. The parent that gets the signal is the
    # pid from the hook, not os.getppid() (this test process).
    result, pid = _child("""
before = threads()
gunicorn_conf().post_worker_init(Worker())
started = threads()
wait_for(lambda: len(kills) >= 2)
result = {"before": before, "started": started, "kills": kills,
          "master": session._gunicorn_master, "ppid": os.getppid()}
""", DASH_STARTUP_GRACE="0.2")
    assert result["before"] == ["MainThread"], result
    assert result["started"] == ["MainThread", "dashboard-watchdog"], result
    assert result["master"] == FAKE_MASTER, result
    assert result["kills"] == [[FAKE_MASTER, TERM], [pid, TERM]], result
    assert result["ppid"] == os.getpid() != FAKE_MASTER


def test_the_last_page_closing_stops_the_server_under_gunicorn():
    result, pid = _child("""
gunicorn_conf().post_worker_init(Worker())
client = app.app.test_client()
post(client, "/ping", "tab")
time.sleep(1.5)
still_up = (list(kills), session._shutting_down)
post(client, "/leaving", "tab")
wait_for(lambda: len(kills) >= 2)
result = {"still_up": still_up, "kills": kills}
""", DASH_STARTUP_GRACE="0.2", DASH_LEAVE_GRACE="0.2")
    assert result["still_up"] == [[], False], result   # an open page keeps it up
    assert result["kills"] == [[FAKE_MASTER, TERM], [pid, TERM]], result


def test_python_app_py_starts_the_watchdog_and_stops_only_itself():
    # `python app.py` calls start_lifecycle() without a master.
    src = (HERE / "app.py").read_text(encoding="utf-8")
    main = src[src.index('if __name__ == "__main__":'):]
    assert "start_lifecycle()" in main and main.index("start_lifecycle()") < main.index("app.run("), main
    result, pid = _child("""
session.start_lifecycle()
started = threads()
wait_for(lambda: len(kills) >= 1)
time.sleep(0.6)   # a second signal would arrive right after the first
result = {"started": started, "kills": kills}
""", DASH_STARTUP_GRACE="0.2")
    assert result["started"] == ["MainThread", "dashboard-watchdog"], result
    assert result["kills"] == [[pid, TERM]], result


def test_without_a_server_entry_disconnect_all_stops_only_this_process():
    # A server that imports app without a hook (the parity test does) has no
    # established master: the facilitator's "Disconnect all" ends it alone.
    result, pid = _child("""
client = app.app.test_client()
post(client, "/ping", "yoda")
status = post(client, "/disconnect-all", "yoda")
wait_for(lambda: len(kills) >= 1)
time.sleep(0.6)
result = {"status": status, "kills": kills}
""")
    assert result == {"status": 204, "kills": [[pid, TERM]]}, result


def test_dash_no_shutdown_keeps_the_server_up_past_every_grace():
    result, pid = _child("""
gunicorn_conf().post_worker_init(Worker())
started = threads()
client = app.app.test_client()
time.sleep(1.5)                     # 7 startup graces without a page
after_startup = (list(kills), session._shutting_down)
post(client, "/ping", "tab")
post(client, "/leaving", "tab")     # the last page closes
wait_for(lambda: not session._clients)  # the watchdog still drops it
dropped = dict(session._clients)
time.sleep(1.5)
after_last_page = (list(kills), session._shutting_down)
# "Disconnect all" is outside the switch (FR-050, scope).
post(client, "/ping", "yoda")
status = post(client, "/disconnect-all", "yoda")
wait_for(lambda: len(kills) >= 2)
result = {"started": started, "after_startup": after_startup, "dropped": dropped,
          "after_last_page": after_last_page, "status": status, "kills": kills}
""", DASH_NO_SHUTDOWN="1", DASH_STARTUP_GRACE="0.2", DASH_LEAVE_GRACE="0.2")
    assert result["started"] == ["MainThread", "dashboard-watchdog"], result
    assert result["after_startup"] == [[], False], result
    assert result["dropped"] == {}, result
    assert result["after_last_page"] == [[], False], result
    assert result["status"] == 204, result
    assert result["kills"] == [[FAKE_MASTER, TERM], [pid, TERM]], result


def test_a_watchdog_pass_with_a_moved_clock():
    # Both modes on one clock, without a thread: the server "started" three
    # hours ago and no page ever connected.
    reasons = []
    real_shutdown, real_started = session._shutdown, session._server_started
    session._shutdown = reasons.append
    try:
        session._server_started = time.monotonic() - 3 * 3600
        assert session._watchdog_pass(auto_stop=False) is False
        assert reasons == []
        assert session._watchdog_pass(auto_stop=True) is True
        assert reasons == ["no browser heartbeat within the startup grace period"]

        # A page connected and went stale: dropped in both modes, a stop only
        # with the automatic stop on.
        del reasons[:]
        with session._lifecycle_lock:
            session._clients["tab"] = time.monotonic() - 3 * 3600
            session._first_seen["tab"] = session._clients["tab"]
            session._ever_connected = True
        assert session._watchdog_pass(auto_stop=False) is False
        assert session._clients == {} and reasons == []
        assert session._watchdog_pass(auto_stop=True) is True
        assert reasons == ["no more browser heartbeat (all tabs closed)"]
    finally:
        session._shutdown, session._server_started = real_shutdown, real_started
        session._ever_connected = False
    assert session._watchdog_started is False   # this process never started one


def _free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _status(port, route="/", body=None):
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}{route}",
        data=None if body is None else json.dumps(body).encode("utf-8"),
        method="GET" if body is None else "POST",
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=3) as resp:
            return resp.status
    except urllib.error.HTTPError as err:
        return err.code
    except OSError:
        return None


def _gunicorn(port, **env):
    """The server of the image and of cli.py, in its own session. Its worker
    signals its master, which is this child and not this test."""
    return subprocess.Popen(
        [sys.executable, "-m", "gunicorn", "--config", str(HERE / "gunicorn.conf.py"),
         "--bind", f"127.0.0.1:{port}", "--worker-class", "gthread",
         "--workers", "1", "--threads", "4", "--no-control-socket", "app:app"],
        cwd=str(HERE), env=dict(os.environ, **env), start_new_session=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def _end(proc):
    if proc.poll() is None:
        os.killpg(proc.pid, signal.SIGKILL)
    proc.wait(timeout=10)
    return proc.stdout.read()


def _wait_until_up(proc, port):
    end = time.monotonic() + 20
    while time.monotonic() < end:
        assert proc.poll() is None, "gunicorn ended before it answered"
        if _status(port) == 200:
            return
        time.sleep(0.1)
    raise AssertionError("gunicorn did not answer")


def test_real_gunicorn_stops_after_the_startup_grace():
    port = _free_port()
    proc = _gunicorn(port, DASH_STARTUP_GRACE="2")
    try:
        _wait_until_up(proc, port)
        try:
            proc.wait(timeout=20)
        except subprocess.TimeoutExpired:
            raise AssertionError("gunicorn still runs 20 s after a startup grace of 2 s")
    finally:
        log = _end(proc)
    assert proc.returncode == 0, (proc.returncode, log)
    # The master ended because the worker sent it SIGTERM.
    assert "Handling signal: term" in log, log


def test_real_gunicorn_with_dash_no_shutdown_runs_until_disconnect_all():
    port = _free_port()
    proc = _gunicorn(port, DASH_NO_SHUTDOWN="1", DASH_STARTUP_GRACE="1", DASH_LEAVE_GRACE="1")
    try:
        _wait_until_up(proc, port)
        time.sleep(4)                                   # 4 startup graces
        assert proc.poll() is None and _status(port) == 200
        assert _status(port, "/ping", {"client_id": "tab"}) == 200
        assert _status(port, "/leaving", {"client_id": "tab"}) == 204
        time.sleep(4)                                   # the last page is gone
        assert proc.poll() is None and _status(port) == 200
        assert _status(port, "/ping", {"client_id": "yoda"}) == 200
        assert _status(port, "/disconnect-all", {"client_id": "yoda"}) == 204
        try:
            proc.wait(timeout=20)
        except subprocess.TimeoutExpired:
            raise AssertionError("gunicorn still runs 20 s after Disconnect all")
    finally:
        log = _end(proc)
    assert proc.returncode == 0, (proc.returncode, log)
    assert "Handling signal: term" in log, log


if __name__ == "__main__":
    test_importing_app_starts_no_thread_and_stops_nothing()
    test_the_gunicorn_hook_starts_the_watchdog_and_only_its_master_is_stopped()
    test_the_last_page_closing_stops_the_server_under_gunicorn()
    test_python_app_py_starts_the_watchdog_and_stops_only_itself()
    test_without_a_server_entry_disconnect_all_stops_only_this_process()
    test_dash_no_shutdown_keeps_the_server_up_past_every_grace()
    test_a_watchdog_pass_with_a_moved_clock()
    test_real_gunicorn_stops_after_the_startup_grace()
    test_real_gunicorn_with_dash_no_shutdown_runs_until_disconnect_all()
    print("all lifecycle start tests passed")
