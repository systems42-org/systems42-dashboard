# _system

Internal machinery for the wiki. Not requirements content — this is *about* the wiki.

- `workflows/` — the operating procedures the agent follows: **capture** (formerly ingest), **inspect**
  (formerly audit; content lint), **relations** (graph/link lint), **report**. `AGENTS.md` points here; `CLAUDE.md` imports `AGENTS.md` for Claude Code.
- `metamodel/` — the explicit metamodel: `meta-metamodel.md` is the
  framework-agnostic language (type, relation, framework, projection, anchor,
  altitude-scale, rule); `types/`, `relations/`, `frameworks/`, `projections/`,
  `altitude.md`, `rules/` are the req42 instances. `scripts/metamodel-lint.py`
  keeps templates and the dashboard catalog in agreement with it.
- `anchors/` — reusable methodological standards (SMART, PAM, user-story-format,
  INVEST, MoSCoW) cited across content types. Method, not domain knowledge; see its
  own README.
- `writing-style.md`: the binding style guide for every text in the repository.
  `AGENTS.md` points to it and `CLAUDE.md` imports it.
- `wiki.yaml` — project identity (system name, tagline). Filled in during
  bootstrap; the dashboard reads it live.
- `scripts/` — standalone maintenance scripts: `new-project.sh` (create a fresh
  wiki from this one, refresh its method files, or harvest method changes made
  there back here as a patch; `make new` / `make sync` / `make harvest`
  wrap it, `test-new-project.sh` tests it) and `concept-cluster-audit.py`
  (deterministic support for `workflows/relations.md`).
- `apps/` — auxiliary applications shipped with the wiki, e.g. `dashboard/`, the
  the Flask app started by `dashboard.sh` (read-only over the wiki; writes only its own settings file).
