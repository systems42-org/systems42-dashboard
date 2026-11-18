# Three stages: `base` holds Python and the requirements, `test` adds what the
# test scripts call (make, node), and the last, unnamed stage is the image
# that ships. `docker build .` and compose build the last stage.
FROM python:3.12-slim AS base

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
    && apt-get install -y --no-install-recommends make nodejs \
    && rm -rf /var/lib/apt/lists/*

FROM base

# One mount (FR-042): the launcher mounts the wiki repository read-only at
# /repo, and its _system/dashboard.yaml writable on top. The dashboard finds
# every folder below /repo by convention (CON-005).
ENV REPO_DIR=/repo

COPY app.py .
COPY catalog.py .
COPY metamodel.py .
COPY preflight.py .
COPY gunicorn.conf.py .
COPY help.md .
COPY VERSION .
COPY templates ./templates
COPY static ./static
COPY brands ./brands

EXPOSE 8000

# One worker keeps the lifecycle state (last-seen timestamp, watchdog) coherent
# in a single process. A few threads handle a page render and the occasional
# lightweight /ping heartbeat concurrently. No request is held open anymore
# (the heartbeat replaced the SSE /events stream), so a small pool suffices and
# can never be starved — /stop is always serviceable. See DR-022.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", \
     "--worker-class", "gthread", "--workers", "1", "--threads", "4", \
     "app:app"]
