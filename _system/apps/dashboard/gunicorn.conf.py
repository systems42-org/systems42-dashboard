"""Read by gunicorn from the working directory (/app in the image)."""
import preflight


def on_starting(server):
    # Before any worker loads the app: say what is missing and stop (CON-005).
    preflight.stop_if_not_a_systems42_wiki()
