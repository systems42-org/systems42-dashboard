# Dashboard distribution and its contract with the metamodel

Notes from a session of Gernot Starke with Claude, 2026-11-14 to 2026-11-17. "Decided" is what Gernot Starke decided. "Proposed" comes from Claude and nobody has agreed it yet. "Today" was checked in the code on 2026-11-17 (`main` 53d2920).

## Decided

1. The dashboard stays in its own repository, systems42-dashboard, with its requirements and its code.
2. Distribution is option 1: a published image plus a thin launcher in each wiki repository. 
3. Project wikis get the dashboard as a pinned image, not as copied code.
4. The dashboard shall assume that the repository it works on is a Systems42 derivative: an LLM wiki holding a metamodel, requirements and architecture, with its configuration. This is to become a constraint.
5. The metamodel is taken from the repository the dashboard runs on.
6. The dashboard derives its section catalog from the framework blocks in the repository it runs on.
7. The dashboard states which metamodel version it supports. If it encounters a mismatch, it will notify users of this mismatch and explain it.
8. Each repository gets its own brand: logo, favicon, intro animation. Systems42 and isaqb-atrium are the showcases. A template "prompt" for such an animation / logo with the required constraints, sizes, data-formats should be part of the dashboard documentation and help
9. isaqb-atrium is the first repository to show all this.

## Proposed

- **One mount.** The launcher mounts the repository root read-only and `_system/dashboard.yaml` writable. The dashboard finds `wiki/`, `raw/sources/`, `docs/`, `_system/metamodel/`, `_system/anchors/` and `_system/wiki.yaml` by convention (note 4). Today the launcher sets eight paths.
- **Thin launcher.** `dashboard.sh` shrinks from 200 lines to about 40: read `dashboard_version:`, start that image, wait until it answers, open the browser.
- **Update.** `./dashboard.sh update` sets `dashboard_version:` to the newest release.
- **Brand lives in its repository.** The atrium brand moves from the dashboard code (`brands/atrium/`) to isaqb-atrium, which names the folder in `brand:`. The systems42 brand stays in the image as the default. This changes FR-032, which lists atrium as a shipped example brand.
- **Metamodel version.** The dashboard reads `version:` from `_system/metamodel/metamodel-version.md`, and warns when it does not support that version.
- Currently we expect a docker (or compatible) container engine to run the dashboard.

## Today

- No image is published: no release workflow, no git tag. `dashboard.sh` builds the image from local code. `VERSION` says 0.9.0.
- isaqb-atrium still holds its own copy of the dashboard code, and has no `brand:` and no `dashboard_version:` in `_system/wiki.yaml`.
- Branding is configuration already (FR-031): `brand:` names a folder with `mark-dark.svg`, `mark-light.svg`, `favicon.svg` and an optional `intro.html`.
- The dashboard reads `_system/metamodel/` and `_system/anchors/` from the repository. It does not read the metamodel's `version: 0.1`.
- The sections differ between repositories: A1 to A5 and C1 to C7 here, A1 to A6 and C1 to C6 in isaqb-atrium (comments in `_system/dashboard.yaml`). We systems42-org/meta should be our reference.


## ensure that "the dashboard depends on the metamodel, never the reverse". shall become a constraint. We can assume that requirements, commons and architecture exists in the metamodel.

The statement does not hold today, and CON-004 does not say it.
Therefore, we have to make it hold and change whatever is needed to make it hold.

- **CON-004 is about requirements, not code.** It says which wiki a requirement belongs to. It says nothing about which code may depend on which.
- **The method depends on the dashboard.** `_system/scripts/metamodel-lint.py` (line 208) imports the dashboard's `catalog.py`.
- **The dashboard restates the metamodel.** `catalog.py` hard-codes each section's id, title, folders and scope. `app.py` hard-codes type prefixes, folders and labels (`_TYPE_FOLDER`, `_TYPE_LABEL`, `FOLDER_LABELS`). The framework blocks and type pages in `_system/metamodel/` declare the same facts.
- **Consequence.** The section catalog travels inside the image, so a repository with other sections, such as isaqb-atrium, is shown with the wrong ones.
- **Already known.** `_system/metamodel/README.md` names the fix as a follow-up of DR-035: derive `catalog.py` and the dictionaries from `frameworks/` and `types/`.
- **What stays in the dashboard.** Routes, colours, navigation labels and tile layout are presentation (`meta-metamodel.md`, "What the meta-meta level deliberately leaves out").
