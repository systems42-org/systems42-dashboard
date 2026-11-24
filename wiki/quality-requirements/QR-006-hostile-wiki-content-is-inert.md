---
id: QR-006
type: quality-requirement
title: Hostile wiki content is inert
status: draft
created: 2026-11-24
updated: 2026-11-24
sources: ["[[SRC-055-recovery-report-systems42-dashboard]]"]
related: ["[[STK-008-workshop-participants-and-facilitators]]", "[[STK-013-people-learning-or-presenting-systems42]]", "[[FR-029-the-dashboard-as-a-product]]", "[[FR-058-a-demo-to-try-without-installing]]", "[[QR-004-the-wikis-content-stays-on-the-machine]]"]
tags: [quality-requirement]
dimensions: [secure]
priority: must
testable: true
---

# Hostile wiki content is inert

**Q42 dimensions.** Secure.

Readers may encounter malicious markup in source material captured into a wiki. The dashboard keeps that content from running or reaching files outside the wiki, including in the public demo.

**Scenario (Q42 quality scenario).**
- **Source.** A workshop participant or a visitor to the public demo ([[STK-008-workshop-participants-and-facilitators]], [[STK-013-people-learning-or-presenting-systems42]]).
- **Stimulus.** Opens a wiki page containing script markup or a link to a file outside the wiki.
- **Environment.** Any dashboard view or the public static demo, with hostile content in a source page.
- **Response.** The content is rendered inert and requests for files outside the wiki are denied.
- **Measure.** The hostile-content checks pass for every rendered page type; no script runs and no file outside the wiki is returned.

**Applies to.** [[FR-029-the-dashboard-as-a-product]] and [[FR-058-a-demo-to-try-without-installing]].
**Tensions.** None known.
