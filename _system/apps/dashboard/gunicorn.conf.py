"""Read by gunicorn from the working directory (/app in the image)."""
import preflight


def on_starting(server):
    # Before any worker loads the app: say what is missing and stop (CON-005).
    preflight.stop_if_not_a_systems42_wiki()


def post_worker_init(worker):
    # In the worker, after it has loaded the app: start the watchdog and name
    # the master it may stop (FR-050). Only here is the parent known to be
    # Gunicorn, so app.py never signals a parent it has to guess (issue #182).
    import app
    app.start_lifecycle(gunicorn_master=worker.ppid)
