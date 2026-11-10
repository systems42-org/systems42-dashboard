#!/usr/bin/env python3
"""Migrate a project's legacy ADRs (_system/adr/) into decision records
(wiki/decisions/, DR-NNN, MADR shape) — DR-034 in the Systems42 meta repository.

    _system/scripts/migrate-decisions.py <project-dir>

Called by `new-project.sh migrate-decisions`. For a project spawned before
decisions became wiki content:

- the project's own ADRs (0004 on) become DR-NNN with the same number,
  `aliases: [ADR-NNNN]`, the Nygard sections renamed to MADR's, and
  "Considered Options" taken from an "Alternatives considered" section or
  marked "Not recorded at the time"; `kind` is left `undefined` for the
  project to set;
- the inherited Systems42 records (0000 template, 0001-0003) are dropped:
  their rules live in AGENTS.md and the templates; links to them become plain
  text;
- [[00NN-…]] links and bare ADR-NNNN in wiki/ pages and _system/index.md are
  rewritten to the DR pages; the index's ADR section becomes "## Decisions";
- _system/adr/ is removed.

Nothing is committed: review with `git status` / `git diff` in the project.
Refuses if a DR-NNN it would write already exists. Standard library only.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

INHERITED = {0, 1, 2, 3}
STATUS = {"accepted": "accepted", "proposed": "review", "superseded": "deprecated",
          "deprecated": "deprecated", "rejected": "deprecated"}


def die(msg: str) -> None:
    sys.exit(f"migrate-decisions: {msg}")


def q(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main() -> None:
    if len(sys.argv) != 2:
        die("usage: migrate-decisions.py <project-dir>")
    root = Path(sys.argv[1]).resolve()
    adr_dir = root / "_system" / "adr"
    out_dir = root / "wiki" / "decisions"
    if not adr_dir.is_dir():
        print(f"Nothing to migrate: {adr_dir} does not exist.")
        return

    own: dict[int, Path] = {}
    for p in sorted(adr_dir.glob("*.md")):
        m = re.match(r"(\d{4})-", p.name)
        if m and int(m.group(1)) not in INHERITED:
            own[int(m.group(1))] = p
    slug = {n: p.stem[5:] for n, p in own.items()}
    dr = {n: f"DR-{n:03d}-{slug[n]}" for n in own}

    out_dir.mkdir(parents=True, exist_ok=True)
    for n in own:
        if list(out_dir.glob(f"DR-{n:03d}-*.md")):
            die(f"wiki/decisions/ already has DR-{n:03d}; resolve that before migrating ADR-{n:04d}")

    link_re = re.compile(r"\[\[(?:ADR-)?(\d{4})(?:-[^\]|#]*)?(?:\|([^\]]*))?\]\]")
    bare_re = re.compile(r"(?<![\w/\[-])ADR-(\d{4})\b")

    def relabel(label: str) -> str:
        return bare_re.sub(lambda m: f"DR-{int(m.group(1)):03d}" if int(m.group(1)) in own else m.group(0), label)

    def rewrite(text: str) -> str:
        def link(m: re.Match) -> str:
            n, label = int(m.group(1)), m.group(2)
            if n in own:
                return f"[[{dr[n]}|{relabel(label) if label else f'DR-{n:03d}'}]]"
            return label or f"ADR-{n:04d}"   # inherited Systems42 record: plain text
        text = link_re.sub(link, text)
        return bare_re.sub(lambda m: (f"[[{dr[int(m.group(1))]}|DR-{int(m.group(1)):03d}]]"
                                      if int(m.group(1)) in own else m.group(0)), text)

    index_lines = []
    for n, p in sorted(own.items()):
        text = p.read_text(encoding="utf-8")
        head, _, body = text.partition("\n## ")
        body = "## " + body if body else ""
        hm = re.match(r"#\s*ADR-\d{4}\s*[:—-]\s*(.+)", head)
        title_md = hm.group(1).strip() if hm else slug[n].replace("-", " ")
        title = re.sub(r"[*`]", "", title_md)
        dm = re.search(r"\*\*Date:\*\*\s*(\S+)", head)
        date = dm.group(1) if dm else ""
        sm = re.search(r"\*\*Status:\*\*\s*(.+)", head)
        status_raw = sm.group(1).strip() if sm else ""
        status = STATUS.get(status_raw.split(";")[0].split()[0].lower() if status_raw else "", "draft")

        body = re.sub(r"^## Context\s*$", "## Context and Problem Statement", body, flags=re.M)
        alt = re.search(r"^## Alternatives considered\s*\n(.*?)(?=^## |\Z)", body, flags=re.M | re.S)
        options = "Not recorded at the time."
        if alt:
            body = body.replace(alt.group(0), "")
            options = alt.group(1).strip()
        # callable replacement: option text is content, not a regex template
        outcome = f"## Considered Options\n\n{options}\n\n## Decision Outcome"
        body = re.sub(r"^## Decision\s*$", lambda _m: outcome,
                      body, count=1, flags=re.M)
        body = re.sub(r"^## Consequences\s*$", "### Consequences", body, flags=re.M)
        # Header bullets beyond Status/Date (Supersedes, Related, …) and any
        # status text beyond the keyword survive as notes, links rewritten.
        notes = []
        if status_raw and len(status_raw.split()) > 1:
            notes.append(f"**Status (as an ADR):** {status_raw}")
        for bm in re.finditer(r"^- \*\*(?!Status|Date)([^*:]+):\*\*\s*(.+?)(?=\n- \*\*|\n\n|\Z)",
                              head, flags=re.M | re.S):
            notes.append(f"**{bm.group(1).strip()}:** " + " ".join(bm.group(2).split()))
        note = "".join(rewrite(x) + "\n\n" for x in notes)
        sup = re.search(r"superseded by\s+(?:\[\[)?(?:ADR-)?(\d{4})", status_raw, flags=re.I)
        sup_by = f'["[[{dr[int(sup.group(1))]}]]"]' if sup and int(sup.group(1)) in own else "[]"
        sup_m = re.search(r"\*\*Supersedes:\*\*\s*(?:\[\[)?(?:ADR-)?(\d{4})", head)
        related = [f'"[[{dr[int(x)]}]]"' for x in
                   ([sup.group(1)] if sup else []) + ([sup_m.group(1)] if sup_m else [])
                   if int(x) in own]

        page = f"""---
id: DR-{n:03d}
type: decision-record
title: {q(title)}
status: {status}
created: {date}
updated: {date}
sources: []
related: [{', '.join(related)}]
tags: [decision-record]
aliases: [ADR-{n:04d}]
kind: undefined
decided: {date}
decision-makers: []
consulted: []
informed: []
amends: []
superseded-by: {sup_by}
---

# {title_md}

> follows [[MADR]] · migrated from `_system/adr/{p.name}` (ADR-{n:04d})

{note}{rewrite(body).strip()}
"""
        (out_dir / f"{dr[n]}.md").write_text(page, encoding="utf-8")
        flag = " (deprecated)" if status == "deprecated" else ""
        index_lines.append(f"- [DR-{n:03d}](../wiki/decisions/{dr[n]}.md) — {title}{flag}.")
        print(f"  ADR-{n:04d} -> wiki/decisions/{dr[n]}.md")

    touched = 0
    for p in sorted((root / "wiki").rglob("*.md")):
        if p.parent == out_dir:
            continue
        old = p.read_text(encoding="utf-8")
        new = rewrite(old)
        if new != old:
            p.write_text(new, encoding="utf-8")
            touched += 1

    index = root / "_system" / "index.md"
    if index.is_file():
        t = index.read_text(encoding="utf-8")
        t = re.sub(r"\n## Architecture Decisions \(ADR\)\n.*?(?=\n## |\Z)", "\n", t, flags=re.S)
        block = "## Decisions\n\n" + "\n".join(index_lines) + ("\n" if index_lines else "") + "\n"
        if re.search(r"^## Decisions\s*$", t, flags=re.M):
            t = re.sub(r"^## Decisions\s*\n\n?", lambda _m: block, t, count=1, flags=re.M)
        elif "\n## Issues\n" in t:
            t = t.replace("\n## Issues\n", "\n" + block + "## Issues\n", 1)
        else:
            t = t.rstrip("\n") + "\n\n" + block
        index.write_text(rewrite(t).rstrip("\n") + "\n", encoding="utf-8")

    for p in adr_dir.glob("*"):
        p.unlink()
    adr_dir.rmdir()

    print(f"Migrated {len(own)} ADR(s) to wiki/decisions/, rewrote links in {touched} wiki page(s),")
    print("dropped the inherited Systems42 records (template, ADR-0001..0003), removed _system/adr/.")
    print("Set each record's `kind` (architecture | business | undefined), then review and commit.")


if __name__ == "__main__":
    main()
