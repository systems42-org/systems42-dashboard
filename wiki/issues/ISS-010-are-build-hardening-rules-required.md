---
id: ISS-010
type: issue
title: Are build-hardening rules required?
status: open
created: 2026-11-24
updated: 2026-11-24
sources: ["[[SRC-055-recovery-report-systems42-dashboard]]", "[[SRC-056-closing-round-on-recovery-report]]"]
related: ["[[DR-004-releases-are-container-images-pinned-per-wiki]]", "[[QR-002-runs-alike-on-linux-and-macos]]", "[[STK-010-operators]]", "[[STK-012-maintainers]]"]
tags: [issue]
severity: major
kind: question
category: architecture
raised-by: agent
owner:
resolved: null
---

# Are build-hardening rules required?

**What's unresolved.** Must the dashboard keep every build dependency pinned, including the container base image, and run its container as an unprivileged user? The recovery report observed both practices, but the human could not confirm whether they are requirements beyond the current state of the art ([[SRC-055-recovery-report-systems42-dashboard]]).

**Affects.** [[DR-004-releases-are-container-images-pinned-per-wiki]], [[QR-002-runs-alike-on-linux-and-macos]], and the work of [[STK-012-maintainers]] and [[STK-010-operators]].

**Context / evidence.** The report found pinned direct and indirect dependencies and a pinned container base image, plus an unprivileged container user. The human left the point for someone with build-security expertise to confirm. The capture closing round records it as open for expert review ([[SRC-056-closing-round-on-recovery-report]]).

**Options.**
1. Treat dependency pinning and least privilege as required practices, then document their scope and checks.
2. Keep them as implementation choices without a promise that every build must follow them.

**Resolution.**
