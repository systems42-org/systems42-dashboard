# Three stages: `base` holds Python and the requirements, `test` adds what the
# test scripts call (make, node, Playwright with Chromium), and the last,
# unnamed stage is the image that ships. `docker build .` and compose build
# the last stage.
#
# The base image is named by digest, so every build starts from the same
# files. To move to a newer python:3.12-slim, take the digest from
#   docker buildx imagetools inspect python:3.12-slim
# (the index digest, which covers amd64 and arm64).
FROM python:3.12-slim@sha256:5e2bdb1b0d542d5039cffb8181c65930093949194a65c365dfb1b0fe13a4fa5b AS base

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# `make test` (dashboard.sh test) runs the test scripts in this stage, with
# the repository mounted. It holds no dashboard code and does not set
# REPO_DIR, so the tests see the code as it is in the repository, on the
# Python and the libraries of the shipped image.
FROM base AS test

RUN apt-get update \
    && apt-get install -y --no-install-recommends make nodejs git \
    && rm -rf /var/lib/apt/lists/*

# The browser test (tests/test_mermaid_browser.py) needs Playwright and its
# Chromium. requirements-dev.txt pins Playwright, and each Playwright release
# pins its own Chromium build. --with-deps adds the system libraries Chromium
# needs, --only-shell takes the headless shell only, which is all the test uses.
COPY requirements-dev.txt .
RUN pip install --no-cache-dir -r requirements-dev.txt \
    && python -m playwright install --with-deps --only-shell chromium \
    && rm -rf /var/lib/apt/lists/*

FROM base

# One mount (FR-042): the launcher mounts the wiki repository read-only at
# /repo. The dashboard writes nothing there. It finds
# every folder below /repo by convention (CON-005).
ENV REPO_DIR=/repo

COPY app.py .
COPY catalog.py .
COPY inputs.py .
COPY metamodel.py .
COPY wiki.py .
COPY preflight.py .
COPY gunicorn.conf.py .
COPY help.md .
COPY VERSION .
COPY templates ./templates
COPY static ./static
COPY brands ./brands

# The dashboard does not run as root. The launcher starts the container as
# the user who called it (`--user`), who can read the mounted repository.
# Started without `--user`, the container runs as this user.
RUN useradd --system --uid 10001 --no-create-home dashboard
USER 10001

EXPOSE 8000

# One worker keeps the lifecycle state (last-seen timestamp, watchdog) coherent
# in a single process. A few threads handle a page render and the occasional
# lightweight /ping heartbeat concurrently. No request is held open anymore
# (the heartbeat replaced the SSE /events stream), so a small pool suffices and
# can never be starved — /stop is always serviceable. See DR-022.
# --no-control-socket: newer gunicorn (26 here) opens a Unix control socket by default;
# nothing here uses it, so it stays off, as it was under gunicorn 23.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", \
     "--worker-class", "gthread", "--workers", "1", "--threads", "4", \
     "--no-control-socket", \
     "app:app"]
